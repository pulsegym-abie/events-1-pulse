<script setup>
import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const ADMIN_PASSWORD = import.meta.env.VITE_ADMIN_PASSWORD

const password = ref('')
const authError = ref('')
const unlocked = ref(false)

const stats = ref(null)
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
    const { data, error } = await supabase.rpc('get_event_stats')
    if (error) throw error
    stats.value = data
  } catch {
    loadError.value = 'Failed to load stats. Try again.'
  } finally {
    loading.value = false
  }
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
        <button type="button" class="btn btn-ghost" :disabled="loading" @click="refresh">
          {{ loading ? 'Refreshing…' : '↻ Refresh' }}
        </button>
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
    </div>
  </div>
</template>

<style scoped>
.admin {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
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
  margin: 0 0 1.2rem;
  text-align: center;
}

.gate {
  width: 100%;
  max-width: 22rem;
}
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

.btn {
  width: 100%;
  background: var(--pulse);
  color: #000;
  border: 0;
  border-radius: 12px;
  font-weight: 700;
  font-size: .95rem;
  padding: .8rem 1rem;
  cursor: pointer;
}
.btn:hover:not(:disabled) { filter: brightness(1.1); }
.btn:disabled { opacity: .55; cursor: default; }

.btn-ghost {
  width: auto;
  background: none;
  border: 1px solid #2a3132;
  color: var(--paper);
}

.err {
  color: var(--danger);
  font-size: .84rem;
  margin: .8rem 0 0;
  text-align: center;
}

.dashboard { width: 100%; max-width: 32rem; }
.dash-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1.4rem;
}
.dash-head h1 { margin: 0; text-align: left; }

.stat-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: .8rem;
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
</style>
