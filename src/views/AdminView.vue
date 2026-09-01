<script setup>
import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const ADMIN_PASSWORD = import.meta.env.VITE_ADMIN_PASSWORD

const password = ref('')
const authError = ref('')
const unlocked = ref(false)

const stats = ref(null)
const registrations = ref([])
const loading = ref(false)
const loadError = ref('')

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
      supabase.rpc('get_event_stats'),
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

function exportCsv() {
  if (!registrations.value.length) return

  const headers = ['Name', 'Phone', 'Email', 'Guests', 'Status', 'Notes', 'Submitted At']
  const rows = registrations.value.map((r) => [
    r.name,
    r.phone,
    r.email || '',
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

      <div v-if="stats" class="stat-grid">
        <div class="stat-card">
          <span class="stat-num">{{ stats.confirmed_count }}</span>
          <span class="stat-label">Confirmed</span>
        </div>
        <div class="stat-card">
          <span class="stat-num">{{ stats.waitlist_count }}</span>
          <span class="stat-label">Waitlist</span>
        </div>
        <div class="stat-card">
          <span class="stat-num">{{ stats.quota }}</span>
          <span class="stat-label">Quota</span>
        </div>
      </div>

      <h2 class="list-head">Registrants ({{ registrations.length }})</h2>
      <div class="table-wrap">
        <table v-if="registrations.length" class="reg-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Phone</th>
              <th>Email</th>
              <th>Guests</th>
              <th>Status</th>
              <th>Notes</th>
              <th>Submitted</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in registrations" :key="r.id">
              <td>{{ r.name }}</td>
              <td>{{ r.phone }}</td>
              <td>{{ r.email || '—' }}</td>
              <td>{{ r.guest_count }}</td>
              <td><span class="badge" :class="r.status">{{ r.status }}</span></td>
              <td>{{ r.notes || '—' }}</td>
              <td>{{ new Date(r.created_at).toLocaleString() }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!loading" class="empty">No registrations yet.</p>
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
  grid-template-columns: repeat(3, 1fr);
  gap: .8rem;
  margin-bottom: 2.2rem;
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

.list-head {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.1rem;
  margin: 0 0 .9rem;
}

.table-wrap {
  overflow-x: auto;
  border: 1px solid #262b2c;
  border-radius: 14px;
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

.empty {
  padding: 1.4rem;
  text-align: center;
  color: var(--muted);
  font-size: .9rem;
}

@media print {
  .gate, .dash-actions, .stat-grid { display: none; }
  .admin { padding: 0; background: #fff; color: #000; }
  .dashboard { max-width: none; }
  .reg-table { color: #000; }
  .reg-table th, .reg-table td { border-color: #ccc; }
  .table-wrap { border: 0; }
}
</style>
