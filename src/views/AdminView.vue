<script setup>
import { ref, reactive, computed } from 'vue'
import { supabase } from '../lib/supabase'

const ADMIN_PASSWORD = import.meta.env.VITE_ADMIN_PASSWORD

const password = ref('')
const authError = ref('')
const unlocked = ref(false)

const stats = ref(null)
const registrations = ref([])
const loading = ref(false)
const loadError = ref('')
const busy = reactive({}) // { [registrationId]: 'approving' | 'declining' }
const actionError = ref('')
const statusFilter = ref('pending') // pending | confirmed | waitlist | declined | all

const filteredRegistrations = computed(() => {
  if (statusFilter.value === 'all') return registrations.value
  return registrations.value.filter(r => r.status === statusFilter.value)
})

const filterTabs = computed(() => [
  { key: 'pending', label: 'Pending', count: stats.value?.pending_count ?? 0 },
  { key: 'confirmed', label: 'Confirmed', count: stats.value?.approved_count ?? 0 },
  { key: 'waitlist', label: 'Waitlist', count: stats.value?.waitlist_count ?? 0 },
  { key: 'declined', label: 'Declined', count: stats.value?.declined_count ?? 0 },
  { key: 'all', label: 'All', count: registrations.value.length }
])

function unlock() {
  if (!ADMIN_PASSWORD) {
    authError.value = 'Admin password is not configured (set VITE_ADMIN_PASSWORD).'
    return
  }
  if (password.value !== ADMIN_PASSWORD) {
    authError.value = 'Wrong password.'
    return
  }
  authError.value = ''
  unlocked.value = true
  refresh()
}

async function refresh() {
  loading.value = true
  loadError.value = ''
  try {
    const [statsRes, regRes] = await Promise.all([
      supabase.rpc('get_admin_stats', { p_password: ADMIN_PASSWORD }),
      supabase.rpc('get_registrations', { p_password: ADMIN_PASSWORD })
    ])
    if (statsRes.error) throw statsRes.error
    if (regRes.error) throw regRes.error
    stats.value = statsRes.data
    registrations.value = regRes.data || []
  } catch (err) {
    loadError.value = err?.message === 'unauthorized'
      ? 'Server rejected the password — set admin_config.password in Supabase to match VITE_ADMIN_PASSWORD.'
      : 'Failed to load data. Try again.'
  } finally {
    loading.value = false
  }
}

async function approveReg(id) {
  if (busy[id]) return
  busy[id] = 'approving'
  actionError.value = ''
  try {
    const { data, error } = await supabase.rpc('approve_registration', { p_password: ADMIN_PASSWORD, p_id: id })
    if (error) throw error
    if (!data.success) throw new Error(data.error || 'approve_failed')
    await refresh()
  } catch (err) {
    actionError.value = 'Could not approve that RSVP. Try again.'
  } finally {
    delete busy[id]
  }
}

async function declineReg(id) {
  if (busy[id]) return
  if (!confirm('Decline this RSVP? This frees their seat for someone else.')) return
  busy[id] = 'declining'
  actionError.value = ''
  try {
    const { data, error } = await supabase.rpc('decline_registration', { p_password: ADMIN_PASSWORD, p_id: id })
    if (error) throw error
    if (!data.success) throw new Error(data.error || 'decline_failed')
    await refresh()
  } catch (err) {
    actionError.value = 'Could not decline that RSVP. Try again.'
  } finally {
    delete busy[id]
  }
}

function waLink(r) {
  const msg = `Hi ${r.name}, thanks for your RSVP — following up about your spot at Pulse Powerhub!`
  return `https://wa.me/${r.phone_normalized}?text=${encodeURIComponent(msg)}`
}

function igLink(r) {
  return `https://instagram.com/${r.instagram}`
}

function exportCsv() {
  if (!registrations.value.length) return

  const headers = ['Name', 'Phone', 'Email', 'Instagram', 'Guests', 'Status', 'Notes', 'Submitted At']
  const rows = registrations.value.map((r) => [
    r.name,
    r.phone,
    r.email || '',
    r.instagram || '',
    r.guest_count,
    r.status,
    r.notes || '',
    new Date(r.created_at).toLocaleString()
  ])
  const escape = (v) => `"${String(v).replace(/"/g, '""')}"`
  const csv = [headers, ...rows].map((row) => row.map(escape).join(',')).join('\r\n')

  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `registrations-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

function exportPdf() {
  window.print()
}
</script>

<template>
  <div class="admin">
    <div v-if="!unlocked" class="gate">
      <p class="brand">PULSE<span class="brand-sub">POWERHUB</span></p>
      <h1>Admin</h1>
      <input
        v-model="password"
        type="password"
        placeholder="Password"
        autocomplete="current-password"
        @keyup.enter="unlock"
      >
      <button type="button" class="btn" @click="unlock">Unlock</button>
      <p v-if="authError" class="err">{{ authError }}</p>
    </div>

    <div v-else class="dashboard">
      <div class="dash-head">
        <h1>Event stats</h1>
        <div class="dash-actions">
          <button type="button" class="btn btn-ghost" @click="exportCsv" :disabled="!registrations.length">
            ⬇ Export CSV
          </button>
          <button type="button" class="btn btn-ghost" @click="exportPdf" :disabled="!registrations.length">
            🖨 Print / PDF
          </button>
          <button type="button" class="btn btn-ghost" :disabled="loading" @click="refresh">
            {{ loading ? 'Refreshing…' : '↻ Refresh' }}
          </button>
        </div>
      </div>

      <p v-if="loadError" class="err">{{ loadError }}</p>
      <p v-if="actionError" class="err">{{ actionError }}</p>

      <div v-if="stats" class="stat-grid">
        <div class="stat-card">
          <span class="stat-num">{{ stats.pending_count }}</span>
          <span class="stat-label">Pending review</span>
        </div>
        <div class="stat-card">
          <span class="stat-num">{{ stats.approved_count }}</span>
          <span class="stat-label">Confirmed</span>
        </div>
        <div class="stat-card">
          <span class="stat-num">{{ stats.waitlist_count }}</span>
          <span class="stat-label">Waitlist</span>
        </div>
        <div class="stat-card">
          <span class="stat-num">{{ stats.quota }}</span>
          <span class="stat-label">Quota ({{ stats.reserved_count }} reserved)</span>
        </div>
      </div>

      <div class="filter-tabs" role="tablist">
        <button
          v-for="f in filterTabs" :key="f.key" type="button" role="tab"
          class="filter-tab" :class="{ active: statusFilter === f.key }"
          @click="statusFilter = f.key"
        >
          {{ f.label }} <span class="filter-count">{{ f.count }}</span>
        </button>
      </div>

      <h2 class="list-head">Registrants ({{ filteredRegistrations.length }} of {{ registrations.length }})</h2>

      <!-- Mobile: compact review cards, one tap per action — the table below
           needs horizontal scroll which is painful for approving many people
           in a row on a phone. -->
      <div class="card-list">
        <div v-for="r in filteredRegistrations" :key="r.id" class="reg-card">
          <div class="reg-card-top">
            <div class="reg-card-who">
              <p class="reg-name">{{ r.name }}</p>
              <a class="reg-phone" :href="'tel:' + r.phone">{{ r.phone }}</a>
              <a v-if="r.instagram" class="reg-ig" :href="igLink(r)" target="_blank" rel="noopener">@{{ r.instagram }}</a>
            </div>
            <span class="badge" :class="r.status">{{ r.status }}</span>
          </div>
          <p v-if="r.notes" class="reg-notes">💬 {{ r.notes }}</p>
          <div class="reg-card-actions">
            <template v-if="r.status === 'pending'">
              <button type="button" class="btn-card btn-approve" :disabled="!!busy[r.id]" @click="approveReg(r.id)">
                {{ busy[r.id] === 'approving' ? 'Confirming…' : '✓ Confirm' }}
              </button>
              <button type="button" class="btn-card btn-decline" :disabled="!!busy[r.id]" @click="declineReg(r.id)">
                {{ busy[r.id] === 'declining' ? '…' : '✕ Decline' }}
              </button>
            </template>
            <button v-else-if="r.status === 'confirmed'" type="button" class="btn-card btn-decline"
                    :disabled="!!busy[r.id]" @click="declineReg(r.id)">
              {{ busy[r.id] === 'declining' ? '…' : 'Revoke' }}
            </button>
            <a v-if="r.phone_normalized" class="btn-card btn-wa" :href="waLink(r)" target="_blank" rel="noopener">WA</a>
            <a v-if="r.instagram" class="btn-card btn-ig" :href="igLink(r)" target="_blank" rel="noopener">IG</a>
          </div>
        </div>
        <p v-if="!filteredRegistrations.length && !loading" class="empty">Nothing here.</p>
      </div>

      <div class="table-wrap">
        <table v-if="filteredRegistrations.length" class="reg-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Phone</th>
              <th>Email</th>
              <th>Instagram</th>
              <th>Guests</th>
              <th>Status</th>
              <th>Notes</th>
              <th>Submitted</th>
              <th class="actions">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in filteredRegistrations" :key="r.id">
              <td>{{ r.name }}</td>
              <td>{{ r.phone }}</td>
              <td>{{ r.email || '—' }}</td>
              <td>
                <a v-if="r.instagram" :href="igLink(r)" target="_blank" rel="noopener">@{{ r.instagram }}</a>
                <span v-else>—</span>
              </td>
              <td>{{ r.guest_count }}</td>
              <td><span class="badge" :class="r.status">{{ r.status }}</span></td>
              <td>{{ r.notes || '—' }}</td>
              <td>{{ new Date(r.created_at).toLocaleString() }}</td>
              <td class="actions">
                <template v-if="r.status === 'pending'">
                  <button type="button" class="btn-mini btn-approve" :disabled="!!busy[r.id]" @click="approveReg(r.id)">
                    {{ busy[r.id] === 'approving' ? '…' : 'Confirm' }}
                  </button>
                  <button type="button" class="btn-mini btn-decline" :disabled="!!busy[r.id]" @click="declineReg(r.id)">
                    {{ busy[r.id] === 'declining' ? '…' : 'Decline' }}
                  </button>
                </template>
                <button v-else-if="r.status === 'confirmed'" type="button" class="btn-mini btn-decline"
                        :disabled="!!busy[r.id]" @click="declineReg(r.id)">
                  {{ busy[r.id] === 'declining' ? '…' : 'Revoke' }}
                </button>
                <span v-else class="muted">—</span>
                <a v-if="r.phone_normalized" class="btn-mini btn-wa" :href="waLink(r)" target="_blank" rel="noopener">WA</a>
                <a v-if="r.instagram" class="btn-mini btn-ig" :href="igLink(r)" target="_blank" rel="noopener">IG</a>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!loading" class="empty">Nothing here.</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.admin {
  min-height: 100vh;
  padding: 2rem 1.2rem;
}

.brand {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: .85rem;
  letter-spacing: .2em;
  margin: 0 0 1.4rem;
  text-align: center;
}
.brand-sub {
  display: block;
  font-weight: 500;
  font-size: .5rem;
  letter-spacing: .45em;
  color: var(--muted);
  margin-top: .2rem;
}

h1 {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.5rem;
  margin: 0;
}

.gate {
  max-width: 22rem;
  margin: 20vh auto 0;
}
.gate h1 { text-align: center; margin-bottom: 1.2rem; }
.gate input {
  width: 100%;
  background: #17171b;
  border: 1px solid rgba(255, 255, 255, .1);
  border-radius: 12px;
  padding: .85rem 1rem;
  color: var(--paper);
  font: inherit;
  font-size: 1rem;
  margin-bottom: .9rem;
}
.gate input:focus { outline: none; border-color: var(--pulse); }
.gate .btn { width: 100%; }

.btn {
  background: var(--pulse);
  color: #000;
  border: 0;
  border-radius: 12px;
  font-weight: 700;
  font-size: .95rem;
  padding: .8rem 1rem;
  cursor: pointer;
  white-space: nowrap;
}
.btn:hover:not(:disabled) { filter: brightness(1.1); }
.btn:disabled { opacity: .45; cursor: default; }

.btn-ghost {
  background: none;
  border: 1px solid #2a3132;
  color: var(--paper);
}

.err {
  color: var(--danger);
  font-size: .84rem;
  margin: .8rem 0 0;
}

.dashboard { max-width: 64rem; margin: 0 auto; }
.dash-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: .8rem;
  margin-bottom: 1.4rem;
}
.dash-actions { display: flex; gap: .6rem; flex-wrap: wrap; }

.stat-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: .8rem;
  margin-bottom: 2.2rem;
}
@media (min-width: 30rem) {
  .stat-grid { grid-template-columns: repeat(4, 1fr); }
}
.stat-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: .3rem;
  border: 1px solid #262b2c;
  border-radius: 16px;
  padding: 1.4rem .5rem;
}
.stat-num {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 2rem;
  color: var(--pulse);
}
.stat-label {
  font-size: .8rem;
  color: var(--muted);
}

.filter-tabs {
  display: flex;
  gap: .5rem;
  overflow-x: auto;
  padding-bottom: .2rem;
  margin-bottom: 1.1rem;
}
.filter-tab {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: .35rem;
  border: 1px solid #262b2c;
  border-radius: 999px;
  background: none;
  color: var(--muted);
  font: inherit;
  font-size: .84rem;
  font-weight: 600;
  padding: .5rem 1rem;
  cursor: pointer;
  white-space: nowrap;
}
.filter-tab.active {
  border-color: var(--pulse);
  color: var(--pulse);
  background: rgba(79, 221, 229, .1);
}
.filter-count {
  font-size: .74rem;
  opacity: .8;
}

.list-head {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.1rem;
  margin: 0 0 .9rem;
}

/* Card list: default (mobile-first) view — one tap-sized card per
   registrant, no horizontal scrolling needed to see or act on a row.
   The full table below is desktop-only (better for scanning/export). */
.card-list {
  display: flex;
  flex-direction: column;
  gap: .7rem;
  margin-bottom: 1.6rem;
}
.reg-card {
  border: 1px solid #262b2c;
  border-radius: 14px;
  padding: 1rem 1.1rem;
  background: rgba(255, 255, 255, .02);
}
.reg-card-top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: .8rem;
}
.reg-card-who { min-width: 0; }
.reg-name {
  margin: 0;
  font-weight: 700;
  font-size: 1rem;
  color: var(--paper);
}
.reg-phone {
  display: block;
  margin-top: .15rem;
  font-size: .84rem;
  color: var(--muted);
  text-decoration: none;
}
.reg-phone:hover { color: var(--pulse); }
.reg-ig {
  display: block;
  margin-top: .1rem;
  font-size: .84rem;
  color: #e1306c;
  text-decoration: none;
}
.reg-ig:hover { text-decoration: underline; }
.reg-notes {
  margin: .6rem 0 0;
  font-size: .84rem;
  color: var(--muted);
  line-height: 1.4;
}
.reg-card-actions {
  display: flex;
  gap: .5rem;
  margin-top: .9rem;
}
.btn-card {
  flex: 1;
  border-radius: 10px;
  border: 1px solid #2a3132;
  background: none;
  color: var(--paper);
  font: inherit;
  font-size: .88rem;
  font-weight: 700;
  padding: .65rem .5rem;
  cursor: pointer;
  text-align: center;
  text-decoration: none;
}
.btn-card:disabled { opacity: .45; cursor: default; }
.btn-card.btn-approve { border-color: var(--pulse); background: var(--pulse); color: #000; }
.btn-card.btn-decline { border-color: var(--danger); color: var(--danger); }
.btn-card.btn-wa { flex: 0 0 auto; padding: .65rem .9rem; border-color: #25D366; color: #25D366; }
.btn-card.btn-ig { flex: 0 0 auto; padding: .65rem .9rem; border-color: #e1306c; color: #e1306c; }

.table-wrap {
  display: none;
  overflow-x: auto;
  border: 1px solid #262b2c;
  border-radius: 14px;
}
@media (min-width: 56rem) {
  .card-list { display: none; }
  .table-wrap { display: block; }
}
.reg-table {
  width: 100%;
  border-collapse: collapse;
  font-size: .86rem;
  white-space: nowrap;
}
.reg-table th, .reg-table td {
  padding: .7rem .9rem;
  text-align: left;
  border-bottom: 1px solid #1b2122;
}
.reg-table th {
  color: var(--muted);
  font-weight: 600;
  font-size: .78rem;
  text-transform: uppercase;
  letter-spacing: .04em;
}
.reg-table tbody tr:last-child td { border-bottom: 0; }

.badge {
  display: inline-block;
  border-radius: 999px;
  padding: .2rem .6rem;
  font-size: .76rem;
  font-weight: 600;
  text-transform: capitalize;
}
.badge.confirmed { background: rgba(79, 221, 229, .15); color: var(--pulse); }
.badge.waitlist { background: rgba(255, 170, 107, .15); color: #ffaa6b; }
.badge.pending { background: rgba(255, 209, 102, .15); color: #ffd166; }
.badge.declined { background: rgba(255, 107, 107, .15); color: var(--danger); }

.actions { display: flex; gap: .4rem; }
.btn-mini {
  display: inline-block;
  border-radius: 8px;
  border: 1px solid #2a3132;
  background: none;
  color: var(--paper);
  font: inherit;
  font-size: .78rem;
  font-weight: 600;
  padding: .35rem .6rem;
  cursor: pointer;
  text-decoration: none;
  white-space: nowrap;
}
.btn-mini:hover:not(:disabled) { filter: brightness(1.15); }
.btn-mini:disabled { opacity: .45; cursor: default; }
.btn-approve { border-color: var(--pulse); color: var(--pulse); }
.btn-decline { border-color: var(--danger); color: var(--danger); }
.btn-wa { border-color: #25D366; color: #25D366; }
.btn-ig { border-color: #e1306c; color: #e1306c; }
.muted { color: var(--muted); }

.empty {
  padding: 1.4rem;
  text-align: center;
  color: var(--muted);
  font-size: .9rem;
}

@media print {
  .gate, .dash-actions, .stat-grid, .actions, .filter-tabs, .card-list { display: none; }
  .admin { padding: 0; background: #fff; color: #000; }
  .dashboard { max-width: none; }
  .table-wrap { display: block; }
  .reg-table { color: #000; }
  .reg-table th, .reg-table td { border-color: #ccc; }
  .table-wrap { border: 0; }
}
</style>
