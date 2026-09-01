<script setup>
import { ref, computed, watch, onBeforeUnmount, nextTick } from 'vue'
import { COUNTRIES, countryByDial, flagOf } from '../lib/countries'

const props = defineProps({
  modelValue: { type: String, default: '' } // dial code, e.g. "+62"
})
const emit = defineEmits(['update:modelValue'])

const open = ref(false)
const query = ref('')
const rootRef = ref(null)
const searchRef = ref(null)

const selected = computed(() => countryByDial(props.modelValue) || null)

const results = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return COUNTRIES
  return COUNTRIES.filter(
    (c) => c.name.toLowerCase().includes(q) || c.dial.includes(q) || c.iso.toLowerCase() === q
  )
})

function toggle () {
  open.value = !open.value
}

function pick (c) {
  emit('update:modelValue', c.dial)
  open.value = false
  query.value = ''
}

function onDocClick (e) {
  if (rootRef.value && !rootRef.value.contains(e.target)) open.value = false
}
function onKey (e) {
  if (e.key === 'Escape') open.value = false
}

watch(open, async (isOpen) => {
  if (isOpen) {
    document.addEventListener('mousedown', onDocClick)
    document.addEventListener('keydown', onKey)
    await nextTick()
    searchRef.value?.focus()
  } else {
    document.removeEventListener('mousedown', onDocClick)
    document.removeEventListener('keydown', onKey)
  }
})

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onDocClick)
  document.removeEventListener('keydown', onKey)
})
</script>

<template>
  <div ref="rootRef" class="cc-select">
    <button type="button" class="cc-trigger" aria-haspopup="listbox" :aria-expanded="open" @click="toggle">
      <span class="cc-flag">{{ selected ? flagOf(selected.iso) : '🌐' }}</span>
      <span class="cc-dial">{{ selected ? selected.dial : '--' }}</span>
      <span class="cc-caret">▼</span>
    </button>

    <div v-if="open" class="cc-menu">
      <div class="cc-search-wrap">
        <input
          ref="searchRef"
          v-model="query"
          type="text"
          placeholder="Search country or code…"
          class="cc-search"
        >
      </div>
      <ul class="cc-list" role="listbox">
        <li v-if="results.length === 0" class="cc-empty">No match.</li>
        <li v-for="c in results" :key="c.iso">
          <button
            type="button"
            class="cc-option"
            :class="{ active: selected?.iso === c.iso }"
            @click="pick(c)"
          >
            <span class="cc-flag">{{ flagOf(c.iso) }}</span>
            <span class="cc-name">{{ c.name }}</span>
            <span class="cc-code">{{ c.dial }}</span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.cc-select {
  position: relative;
  flex-shrink: 0;
}

.cc-trigger {
  display: flex;
  align-items: center;
  gap: .3rem;
  height: 2.5rem;
  padding: 0 .4rem;
  background: none;
  border: 0;
  color: var(--paper);
  font: inherit;
  font-size: .95rem;
  font-weight: 600;
  cursor: pointer;
}
.cc-flag { font-size: 1.05rem; line-height: 1; }
.cc-caret { font-size: .55rem; color: var(--muted); }

.cc-menu {
  position: absolute;
  z-index: 10;
  top: calc(100% + .4rem);
  left: 0;
  width: 17rem;
  max-width: 80vw;
  background: #17171b;
  border: 1px solid rgba(255, 255, 255, .1);
  border-radius: 14px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, .5);
  overflow: hidden;
}

.cc-search-wrap {
  padding: .6rem;
  border-bottom: 1px solid rgba(255, 255, 255, .08);
}
.cc-search {
  width: 100%;
  height: 2.3rem;
  background: #0d0d0f;
  border: 1px solid rgba(255, 255, 255, .08);
  border-radius: 10px;
  padding: 0 .7rem;
  color: var(--paper);
  font: inherit;
  font-size: .88rem;
}
.cc-search:focus { outline: none; border-color: var(--pulse); }
.cc-search::placeholder { color: var(--muted); }

.cc-list {
  list-style: none;
  margin: 0;
  padding: .3rem 0;
  max-height: 16rem;
  overflow-y: auto;
}
.cc-empty {
  padding: .8rem;
  text-align: center;
  font-size: .85rem;
  color: var(--muted);
}
.cc-option {
  width: 100%;
  display: flex;
  align-items: center;
  gap: .6rem;
  background: none;
  border: 0;
  padding: .5rem .8rem;
  color: var(--paper);
  font: inherit;
  font-size: .88rem;
  text-align: left;
  cursor: pointer;
}
.cc-option:hover, .cc-option.active { background: rgba(79, 221, 229, .1); }
.cc-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cc-code { color: var(--muted); font-variant-numeric: tabular-nums; }
</style>
