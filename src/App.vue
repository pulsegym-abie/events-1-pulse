<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from './lib/supabase'
import { isValidPhoneNumber } from './lib/phoneValidation'
import CountryCodeSelect from './components/CountryCodeSelect.vue'

// Nilai bawaan sebelum content.md selesai di-fetch (juga fallback kalau file itu hilang)
const content = reactive({
  brand: 'PULSE',
  brandSub: 'POWERHUB',
  badge: '🌐 Public Event',
  title: 'PULSE 1st Anniversary',
  coverImage: '/cover.jpg',
  coverAlt: 'PULSE Powerhub 1st Anniversary — join the celebration',
  dateShort: 'Wednesday, Sep 9',
  dateFull: 'September 9, 2026',
  time: '5:00 PM – 8:00 PM',
  startIso: '2026-09-09T17:00:00+08:00',
  hostName: 'Pulse Powerhub',
  hostInitials: 'PP',
  venue: 'Pulse Powerhub',
  address: 'Jl. Pemelisan Agung, Pantai Berawa, Tibubeneng, Canggu, Bali',
  mapsLink: 'https://maps.google.com/?q=Pulse+Powerhub+Berawa+Canggu',
  tagline: 'Stronger together',
  instagramHandle: '@pulsepowerhub.bali',
  instagramLink: 'https://instagram.com/pulsepowerhub.bali',
  lineup: ['Fitness challenge', 'Recovery & sauna', 'DJ set', 'Food & drinks', 'Prizes', 'Bazaar', 'Tarot booth', 'IV drip booth'],
  description: 'One year of fitness, wellness and community in Berawa.\nJoin us for an evening of movement, music, food and good company.',
  dressCode: '',
  morningSpecialTime: '',
  morningSpecialTitle: '',
  morningSpecialNote: '',
  // Setiap item "Nama|/path/logo.jpg" — format sederhana ini dipakai supaya sponsor
  // tetap bisa diedit lewat content.md tanpa perlu ubah parser (masih list biasa).
  sponsors: []
})

const sponsorList = computed(() => content.sponsors
  .map(entry => {
    const [name, logo] = entry.split('|')
    return { name: (name || '').trim(), logo: (logo || '').trim() }
  })
  .filter(s => s.name && s.logo))

const stats = ref(null) // { quota, confirmed_count, waitlist_count }
const spotsLeft = computed(() => {
  if (!stats.value) return null
  return Math.max(0, stats.value.quota - stats.value.confirmed_count)
})
const shared = ref(false)

const rsvpOpen = ref(false)

const form = reactive({
  name: '',
  phoneDial: '', // country dial code, e.g. "+62" — left blank, most guests aren't Indonesian
  phone: '', // national number, without the dial code
  email: '',
  comment: '',
  website: '' // honeypot — hidden from real visitors, see .hp-field below
})

const errors = reactive({})
const status = ref('idle') // idle | sending | done | waitlisted | already | error
const errorMessage = ref('')
const revealed = ref(false)

const daysLeft = computed(() => {
  const diff = new Date(content.startIso) - new Date()
  return Math.max(0, Math.ceil(diff / 86400000))
})

const calendarUrl = computed(() => {
  const start = new Date(content.startIso)
  const end = new Date(start.getTime() + 3 * 60 * 60 * 1000)
  const fmt = d => d.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
  const params = new URLSearchParams({
    action: 'TEMPLATE',
    text: content.title,
    dates: `${fmt(start)}/${fmt(end)}`,
    location: content.address,
    details: content.description
  })
  return `https://calendar.google.com/calendar/render?${params}`
})

onMounted(async () => {
  requestAnimationFrame(() => { revealed.value = true })
  await loadContent()
  fetchStats()
})

/** Parser ringan untuk content.md: frontmatter `key: value` (+ list `- item`), lalu `---`, lalu deskripsi bebas */
function parseContentMd (text) {
  const [metaBlock, ...rest] = text.split(/\r?\n---\r?\n/)
  const data = {}
  let listKey = null

  metaBlock.split(/\r?\n/).forEach(line => {
    const listItem = line.match(/^\s*-\s+(.*)$/)
    if (listItem && listKey) {
      data[listKey].push(listItem[1].trim())
      return
    }
    const kv = line.match(/^([a-zA-Z_]+):\s*(.*)$/)
    if (!kv) return
    const key = kv[1].trim().replace(/_([a-z])/g, (_, c) => c.toUpperCase())
    const value = kv[2].trim()
    if (value === '') {
      data[key] = []
      listKey = key
    } else {
      data[key] = value
      listKey = null
    }
  })

  const description = rest.join('\n---\n').trim()
  if (description) data.description = description

  return data
}

async function loadContent () {
  try {
    const res = await fetch('/content.md')
    if (!res.ok) return
    const text = await res.text()
    Object.assign(content, parseContentMd(text))
  } catch {
    // content.md belum ada / gagal dimuat — tetap pakai nilai bawaan
  }
}

async function fetchStats () {
  try {
    const { data, error } = await supabase.rpc('get_event_stats')
    if (error) throw error
    stats.value = data
  } catch {
    // spots-row falls back to "Limited spots" — not worth surfacing an error for this
  }
}

function openRsvp () {
  rsvpOpen.value = true
}

function closeRsvp () {
  rsvpOpen.value = false
}

async function share () {
  const shareData = {
    title: content.title,
    text: `${content.title} — ${content.dateFull}`,
    url: window.location.href
  }

  if (navigator.share) {
    try { await navigator.share(shareData) } catch { /* user cancelled */ }
    return
  }

  try {
    await navigator.clipboard.writeText(window.location.href)
    shared.value = true
    setTimeout(() => { shared.value = false }, 2000)
  } catch { /* clipboard unavailable, silently ignore */ }
}

function validate () {
  Object.keys(errors).forEach(k => delete errors[k])

  if (form.name.trim().length < 2) {
    errors.name = 'Enter your full name.'
  }

  if (!form.phoneDial) {
    errors.phone = 'Select your country code.'
  } else if (!isValidPhoneNumber(form.phone)) {
    errors.phone = 'Enter a valid WhatsApp number.'
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(form.email.trim())) {
    errors.email = 'Enter a valid email address.'
  }

  return Object.keys(errors).length === 0
}

async function submit () {
  if (status.value === 'sending') return

  // Honeypot: real visitors never see or fill this field — bots that do get
  // silently dropped, no error, no request sent.
  if (form.website) return

  if (!validate()) return

  status.value = 'sending'
  errorMessage.value = ''

  try {
    const { data, error } = await supabase.rpc('submit_registration', {
      p_name: form.name.trim(),
      p_phone: form.phoneDial + form.phone.trim(),
      p_email: form.email.trim().toLowerCase(),
      p_notes: form.comment.trim() || null
    })
    if (error) throw error

    if (!data.success) {
      if (data.error === 'already_registered') {
        status.value = 'already'
        return
      }
      throw new Error(data.error || 'Save failed')
    }

    status.value = data.status === 'waitlist' ? 'waitlisted' : 'done'
    fetchStats()
  } catch (err) {
    status.value = 'error'
    errorMessage.value = 'We could not save your RSVP. Check your connection and try again.'
  }
}

function retry () {
  status.value = 'idle'
  errorMessage.value = ''
}
</script>

<template>
  <div class="page" :class="{ 'is-revealed': revealed }">

    <header class="hero">
      <div class="title-block">
        <p class="brand">{{ content.brand }}<span class="brand-sub">{{ content.brandSub }}</span></p>

        <span class="event-badge">{{ content.badge }}</span>
        <h1 class="event-title">{{ content.title }}</h1>
      </div>

      <div class="flyer-block">
        <img class="cover" :src="content.coverImage" :alt="content.coverAlt">
        <div class="flyer-actions">
          <button type="button" class="rsvp-btn" @click="openRsvp">
            {{ spotsLeft !== null && spotsLeft <= 0 ? '📝 Join Waitlist' : '🔥 RSVP' }}
          </button>
        </div>
      </div>

      <div class="intro">
        <p class="event-date">{{ content.dateShort }}</p>
        <p class="event-time">{{ content.time }}</p>

        <div class="quick-actions">
          <a class="pill-btn" :href="calendarUrl" target="_blank" rel="noopener">🕐 Add to calendar</a>
          <button class="icon-btn" type="button" @click="share" :aria-label="shared ? 'Link copied' : 'Share invite'">
            {{ shared ? '✓' : '↗' }}
          </button>
        </div>

        <p class="label">👑 Hosted by</p>
        <div class="host-row">
          <span class="avatar" aria-hidden="true">{{ content.hostInitials }}</span>
          <p class="host-line">{{ content.hostName }}</p>
        </div>

        <a class="location-block" :href="content.mapsLink" target="_blank" rel="noopener">
          <span class="detail-icon">📍</span>
          <span>
            <strong>{{ content.venue }}</strong>
            <br><span class="addr">{{ content.address }}</span>
          </span>
        </a>

        <p class="spots-row">
          <span class="detail-icon">👥</span>
          <span :class="{ 'is-low': spotsLeft !== null && spotsLeft <= 20 }">
            {{ spotsLeft === null ? 'Limited spots' : spotsLeft <= 0 ? 'Fully booked — waitlist open' : `${spotsLeft}/${stats.quota} spots left` }}
          </span>
        </p>

        <p class="tagline">{{ content.tagline }}</p>

        <p class="lede">{{ content.description }}</p>

        <p v-if="daysLeft > 0" class="counter">{{ daysLeft }} days to go</p>
      </div>
    </header>

    <section class="lineup" aria-label="What's happening">
      <h2 class="section-head">What's happening</h2>
      <ul class="chips">
        <li v-for="item in content.lineup" :key="item">{{ item }}</li>
      </ul>
    </section>

    <section v-if="content.dressCode || content.morningSpecialTitle" class="info-section" aria-label="Good to know">
      <h2 class="section-head">Good to know</h2>
      <div class="info-grid">
        <div v-if="content.dressCode" class="info-card">
          <p class="info-label">👕 Dress code</p>
          <p class="info-value">{{ content.dressCode }}</p>
        </div>
        <div v-if="content.morningSpecialTitle" class="info-card">
          <p class="info-label">🧘 Morning special · {{ content.morningSpecialTime }}</p>
          <p class="info-value">{{ content.morningSpecialTitle }}</p>
          <p v-if="content.morningSpecialNote" class="info-note">{{ content.morningSpecialNote }}</p>
        </div>
      </div>
    </section>

    <section v-if="sponsorList.length" class="sponsors-section" aria-label="Supported by">
      <h2 class="section-head">Supported by</h2>
      <ul class="sponsor-grid">
        <li v-for="s in sponsorList" :key="s.name" class="sponsor-tile">
          <img :src="s.logo" :alt="s.name" loading="lazy">
        </li>
      </ul>
    </section>

    <footer class="foot">
      <a :href="content.instagramLink" target="_blank" rel="noopener">{{ content.instagramHandle }}</a>
      <span>{{ content.address }}</span>
    </footer>

    <div class="sticky-bar">
      <div class="pill-group">
        <button type="button" class="rsvp-btn" @click="openRsvp">
          {{ spotsLeft !== null && spotsLeft <= 0 ? '📝 Join Waitlist' : '🔥 RSVP' }}
        </button>
      </div>
    </div>

    <div v-if="rsvpOpen" class="modal-overlay" @click.self="closeRsvp">
      <div class="modal-sheet" role="dialog" aria-modal="true" aria-label="RSVP">

        <template v-if="status === 'idle' || status === 'sending' || status === 'error'">
          <div class="uline-field">
            <input v-model="form.name" type="text" placeholder="Your Name" autocomplete="name"
                   :aria-invalid="!!errors.name" @input="delete errors.name">
          </div>
          <p v-if="errors.name" class="err">{{ errors.name }}</p>

          <div class="uline-field phone-field">
            <CountryCodeSelect v-model="form.phoneDial" />
            <input v-model="form.phone" type="tel" inputmode="tel" placeholder="Phone number" autocomplete="tel"
                   :aria-invalid="!!errors.phone" @input="delete errors.phone">
          </div>
          <p class="hint">Just for event updates. No spam.</p>
          <p v-if="errors.phone" class="err">{{ errors.phone }}</p>

          <div class="uline-field">
            <input v-model="form.email" type="email" placeholder="Email" autocomplete="email"
                   :aria-invalid="!!errors.email" @input="delete errors.email">
          </div>
          <p v-if="errors.email" class="err">{{ errors.email }}</p>

          <div class="uline-field">
            <input v-model="form.comment" type="text" placeholder="+ Post a comment">
          </div>

          <!-- Honeypot: hidden from real visitors via CSS, tabindex/autocomplete
               discourage autofill. Any bot that fills it gets silently dropped
               in submit() — see .hp-field below. -->
          <div class="hp-field" aria-hidden="true">
            <label>
              Company
              <input v-model="form.website" type="text" tabindex="-1" autocomplete="off">
            </label>
          </div>

          <p v-if="status === 'error'" class="err err-block">
            {{ errorMessage }}
            <button class="link" type="button" @click="retry">Try again</button>
          </p>

          <div class="modal-footer">
            <button type="button" class="link-cancel" @click="closeRsvp">Cancel</button>
            <button type="button" class="btn-continue" :disabled="status === 'sending'" @click="submit">
              {{ status === 'sending' ? 'Saving…' : 'Continue' }}
            </button>
          </div>
        </template>

        <template v-else-if="status === 'done'">
          <h2 class="panel-head">You're on the list</h2>
          <p class="panel-note">
            See you on {{ content.dateFull }} at {{ content.time }}.
            We'll send the details to {{ form.email }}.
          </p>
          <a class="cta cta-link" :href="calendarUrl" target="_blank" rel="noopener">
            Add to Google Calendar
          </a>
          <a class="link link-block" :href="content.mapsLink"
             target="_blank" rel="noopener">Open in Maps</a>
          <div class="modal-footer modal-footer-single">
            <button type="button" class="btn-continue" @click="closeRsvp">Done</button>
          </div>
        </template>

        <template v-else-if="status === 'waitlisted'">
          <h2 class="panel-head">You're on the waitlist</h2>
          <p class="panel-note">
            Spots are full for {{ content.dateFull }}, but you're on the waitlist —
            we'll reach out on WhatsApp if a spot opens up.
          </p>
          <div class="modal-footer modal-footer-single">
            <button type="button" class="btn-continue" @click="closeRsvp">Got it</button>
          </div>
        </template>

        <template v-else-if="status === 'already'">
          <h2 class="panel-head">You're already registered</h2>
          <p class="panel-note">
            This phone number or email is already on our list for {{ content.dateFull }}. See you there!
          </p>
          <div class="modal-footer modal-footer-single">
            <button type="button" class="btn-continue" @click="closeRsvp">Close</button>
          </div>
        </template>

      </div>
    </div>

  </div>
</template>

<style scoped>
.page {
  max-width: 46rem;
  margin: 0 auto;
  padding: 2.4rem 1.5rem 6.5rem;
}

@media (min-width: 60rem) {
  .page { max-width: 68rem; padding-bottom: 4rem; }
}

/* one orchestrated entrance, nothing else moves on its own */
.hero, .lineup {
  opacity: 0;
  transform: translateY(12px);
  transition: opacity .5s ease, transform .5s ease;
}
.is-revealed .hero { opacity: 1; transform: none; transition-delay: .05s; }
.is-revealed .lineup { opacity: 1; transform: none; transition-delay: .18s; }

@media (prefers-reduced-motion: reduce) {
  .hero, .lineup {
    opacity: 1; transform: none; transition: none;
  }
}

/* --- hero: single column on mobile; Partiful-style 2-col + sticky flyer on desktop --- */
.title-block { grid-area: title; }
.flyer-block { grid-area: flyer; }
.intro { grid-area: intro; }
.flyer-actions { display: none; }

@media (min-width: 60rem) {
  .hero {
    display: grid;
    grid-template-columns: 1fr 24rem;
    grid-template-areas:
      "title flyer"
      "intro flyer";
    column-gap: 3.5rem;
    align-items: start;
  }
  .flyer-block { position: sticky; top: 2.4rem; }
  .flyer-actions { display: block; margin-top: 1.2rem; }
}

.brand {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.05rem;
  letter-spacing: .22em;
  margin: 0 0 1.6rem;
  color: var(--paper);
}
.brand-sub {
  display: block;
  font-family: 'Inter', sans-serif;
  font-weight: 500;
  font-size: .58rem;
  letter-spacing: .5em;
  color: var(--muted);
  margin-top: .2rem;
}

.event-badge {
  display: inline-flex;
  align-items: center;
  gap: .35rem;
  border: 1px solid rgba(255, 255, 255, .25);
  border-radius: 999px;
  padding: .35rem .9rem;
  font-size: .78rem;
  color: #d4d9da;
  background: rgba(255, 255, 255, .06);
}
.event-title {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: clamp(1.5rem, 5.5vw, 2.1rem);
  line-height: 1.15;
  margin: .9rem 0 1.3rem;
  background: linear-gradient(100deg, var(--paper) 45%, var(--pulse) 90%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* --- cover photo + flyer actions (Partiful-style sticky sidebar on desktop) --- */
.cover {
  display: block;
  width: 100%;
  aspect-ratio: 1000 / 524;
  object-fit: cover;
  border-radius: 20px;
  margin: 0 0 1.8rem;
  box-shadow: 0 0 40px rgba(79, 221, 229, .12);
}

/* --- intro block --- */
.event-date {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: clamp(1.7rem, 6vw, 2.2rem);
  line-height: 1.1;
  margin: 0;
}
.event-time {
  margin: .3rem 0 0;
  font-size: 1rem;
  color: var(--muted);
}

.quick-actions {
  display: flex;
  align-items: center;
  gap: .7rem;
  margin: 1.2rem 0 0;
}
.pill-btn {
  display: inline-flex;
  align-items: center;
  gap: .4rem;
  border: 1px solid #2a3132;
  border-radius: 999px;
  padding: .55rem 1.05rem;
  font-size: .86rem;
  font-weight: 500;
  color: var(--paper);
  text-decoration: none;
}
.pill-btn:hover { border-color: var(--pulse); color: var(--pulse); }
.icon-btn {
  width: 2.7rem;
  height: 2.7rem;
  border-radius: 50%;
  border: 1px solid #2a3132;
  background: none;
  color: var(--paper);
  font-size: 1.05rem;
  cursor: pointer;
  flex-shrink: 0;
}
.icon-btn:hover { border-color: var(--pulse); color: var(--pulse); }

.label {
  margin: 1.8rem 0 .6rem;
  font-size: .8rem;
  letter-spacing: .04em;
  color: var(--muted);
}

.host-row {
  display: flex;
  align-items: center;
  gap: .65rem;
  margin: 0;
}
.avatar {
  display: grid;
  place-items: center;
  width: 2.1rem;
  height: 2.1rem;
  border-radius: 50%;
  background: var(--pulse);
  color: #000;
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: .76rem;
  letter-spacing: .02em;
  flex-shrink: 0;
  box-shadow: 0 0 0 0 rgba(79, 221, 229, .5);
  animation: avatar-pulse 2.6s ease-out infinite;
}
@keyframes avatar-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(79, 221, 229, .45); }
  70%  { box-shadow: 0 0 0 .5rem rgba(79, 221, 229, 0); }
  100% { box-shadow: 0 0 0 0 rgba(79, 221, 229, 0); }
}
@media (prefers-reduced-motion: reduce) {
  .avatar { animation: none; }
}
.host-line {
  margin: 0;
  font-size: .96rem;
  font-weight: 600;
  color: var(--paper);
}

.location-block {
  display: flex;
  gap: .7rem;
  margin: 1.5rem 0 0;
  color: inherit;
  text-decoration: none;
}
.location-block strong {
  display: block;
  color: var(--paper);
  font-weight: 600;
  font-size: .96rem;
}
.location-block .addr {
  color: var(--muted);
  font-size: .86rem;
}
.location-block:hover strong { color: var(--pulse); }

.spots-row {
  display: flex;
  align-items: center;
  gap: .7rem;
  margin: 1.1rem 0 0;
  font-size: .95rem;
  color: #d4d9da;
}
.spots-row .is-low { color: var(--danger); font-weight: 600; }

.detail-icon {
  width: 1.4rem;
  flex-shrink: 0;
  text-align: center;
}

.title {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: clamp(1.3rem, 4.5vw, 1.6rem);
  letter-spacing: .02em;
  text-transform: uppercase;
  margin: 1.9rem 0 0;
}

.tagline {
  font-weight: 600;
  font-style: italic;
  font-size: 1rem;
  letter-spacing: .1em;
  color: var(--pulse);
  margin: .5rem 0 0;
}

.lede {
  font-family: 'General Sans', 'Inter', sans-serif;
  font-weight: 400;
  max-width: 34ch;
  font-size: 1.02rem;
  line-height: 1.55;
  color: #d4d9da;
  margin: 1.3rem 0 0;
  white-space: pre-line;
}

.counter {
  display: inline-block;
  margin: 1.6rem 0 0;
  font-size: .8rem;
  letter-spacing: .16em;
  color: var(--muted);
  border-bottom: 1px solid var(--pulse-dim);
  padding-bottom: .3rem;
}

/* --- lineup --- */
.lineup { margin: 3rem 0 0; }
.section-head {
  position: relative;
  display: inline-block;
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.5rem;
  letter-spacing: .02em;
  margin: 0 0 1.3rem;
}
.section-head::after {
  content: '';
  position: absolute;
  left: 0;
  bottom: -.4rem;
  width: 2.4rem;
  height: 3px;
  border-radius: 999px;
  background: linear-gradient(90deg, var(--pulse), transparent);
}
.chips {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: .5rem;
}
.chips li {
  border: 1px solid #262b2c;
  border-radius: 999px;
  padding: .42rem .85rem;
  font-size: .88rem;
  color: #c3c9ca;
}

/* --- rsvp modal --- */
.modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 50;
  background: rgba(0, 0, 0, .6);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: flex-end;
  justify-content: center;
}
.modal-sheet {
  width: 100%;
  max-width: 30rem;
  max-height: 88vh;
  overflow-y: auto;
  background: #101314;
  border-radius: 20px 20px 0 0;
  padding: 1.7rem 1.4rem calc(1.3rem + env(safe-area-inset-bottom));
  box-shadow: 0 -12px 40px rgba(0, 0, 0, .5);
}
@media (min-width: 30rem) {
  .modal-overlay { align-items: center; }
  .modal-sheet { border-radius: 20px; }
}

.panel-head {
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.8rem;
  margin: 0;
}
.panel-note {
  color: var(--muted);
  font-size: .94rem;
  margin: .45rem 0 1.7rem;
  line-height: 1.5;
}

.uline-field { margin: 0 0 1.2rem; }
.uline-field input {
  width: 100%;
  background: none;
  border: 0;
  border-bottom: 1px solid #2a3132;
  color: var(--paper);
  font: inherit;
  font-size: 1rem;
  padding: .6rem 0;
}
.uline-field input::placeholder { color: var(--muted); }
.uline-field input:focus { outline: none; border-color: var(--pulse); }
.uline-field input[aria-invalid='true'] { border-color: var(--danger); }

.phone-field {
  display: flex;
  align-items: center;
  gap: .3rem;
  border-bottom: 1px solid #2a3132;
}
.phone-field input { border-bottom: 0; flex: 1; }

.hint { margin: -.85rem 0 1.2rem; font-size: .78rem; color: var(--muted); }

/* Honeypot — off-screen, not display:none (some bots skip hidden fields). */
.hp-field {
  position: absolute;
  left: -9999px;
  width: 1px;
  height: 1px;
  overflow: hidden;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 1.4rem;
}
.modal-footer-single { justify-content: flex-end; }
.link-cancel {
  background: none;
  border: 0;
  color: var(--muted);
  font: inherit;
  font-size: .95rem;
  cursor: pointer;
}
.link-cancel:hover { color: var(--paper); }
.btn-continue {
  background: var(--pulse);
  color: #000;
  border: 0;
  border-radius: 10px;
  font-weight: 700;
  font-size: .95rem;
  padding: .75rem 1.6rem;
  cursor: pointer;
}
.btn-continue:disabled { opacity: .55; cursor: default; }
.btn-continue:hover:not(:disabled) { filter: brightness(1.1); }

.err {
  color: var(--danger);
  font-size: .84rem;
  margin: .4rem 0 .8rem;
}
.err-block { margin-top: .9rem; }

.cta {
  display: block;
  width: 100%;
  margin-top: .6rem;
  background: var(--pulse);
  color: #000;
  border: 0;
  border-radius: 9px;
  font-family: 'Plus Jakarta Sans', sans-serif;
  font-weight: 800;
  font-size: 1.05rem;
  letter-spacing: .06em;
  padding: .95rem 1rem;
  cursor: pointer;
  transition: filter .15s ease;
}
.cta:hover:not(:disabled) { filter: brightness(1.12); }
.cta:disabled { opacity: .55; cursor: default; }
.cta:focus-visible { outline: 2px solid var(--paper); outline-offset: 3px; }

.cta-link {
  text-align: center;
  text-decoration: none;
  margin-top: 1.4rem;
}

.link {
  background: none;
  border: 0;
  color: var(--pulse);
  font: inherit;
  text-decoration: underline;
  cursor: pointer;
  padding: 0 0 0 .35rem;
}
.link-block {
  display: block;
  text-align: center;
  margin-top: 1rem;
  padding: 0;
  font-size: .92rem;
}

/* --- good to know (dress code / morning special) --- */
.info-section { margin: 3rem 0 0; }
.info-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: .8rem;
}
@media (min-width: 30rem) {
  .info-grid { grid-template-columns: 1fr 1fr; }
}
.info-card {
  border: 1px solid #262b2c;
  border-radius: 14px;
  padding: 1rem 1.15rem;
  background: rgba(255, 255, 255, .03);
}
.info-label {
  margin: 0 0 .35rem;
  font-size: .78rem;
  letter-spacing: .04em;
  color: var(--muted);
}
.info-value {
  margin: 0;
  font-size: .98rem;
  font-weight: 600;
  color: var(--paper);
}
.info-note {
  margin: .35rem 0 0;
  font-size: .84rem;
  color: var(--muted);
  line-height: 1.5;
}

/* --- supported by / sponsors --- */
.sponsors-section { margin: 3rem 0 0; }
.sponsor-grid {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: .8rem;
}
@media (min-width: 30rem) {
  .sponsor-grid { grid-template-columns: repeat(3, 1fr); }
}
.sponsor-tile {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 5.5rem;
  border-radius: 14px;
  background: #f5f2ee;
  padding: .9rem;
}
.sponsor-tile img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}

/* --- footer --- */
.foot {
  margin: 3.5rem 0 0;
  padding-top: 1.4rem;
  border-top: 1px solid #1b2122;
  display: flex;
  flex-wrap: wrap;
  gap: .5rem 1.5rem;
  justify-content: space-between;
  font-size: .86rem;
  color: var(--muted);
}
.foot a { color: var(--pulse); text-decoration: none; }
.foot a:hover { text-decoration: underline; }

/* --- floating RSVP pill --- */
.sticky-bar {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 20;
  display: flex;
  justify-content: center;
  padding: 0 1.2rem calc(1.1rem + env(safe-area-inset-bottom));
  pointer-events: none;
}
@media (min-width: 60rem) {
  /* RSVP lives inline under the flyer image on desktop instead. */
  .sticky-bar { display: none; }
}
.pill-group {
  pointer-events: auto;
  width: 100%;
  max-width: 26rem;
}

/* Shared RSVP button look — the sticky mobile bar and the desktop flyer
   sidebar both use it, so it always reads as the one action that matters. */
.rsvp-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  padding: 1.15rem 1.5rem;
  border-radius: 999px;
  font-family: inherit;
  font-weight: 700;
  font-size: 1.05rem;
  white-space: nowrap;
  cursor: pointer;
  background: var(--pulse);
  color: #000;
  border: 0;
  box-shadow: 0 12px 32px rgba(0, 0, 0, .45);
  transition: filter .15s ease;
}
.rsvp-btn:hover { filter: brightness(1.08); }
.rsvp-btn:active { filter: brightness(0.95); }

@media (max-width: 30rem) {
  .page { padding: 2rem 1.15rem 7rem; }
  .rsvp-btn { padding: 1.05rem 1.3rem; }
}
</style>
