# Pulse Powerhub RSVP — Setup

## 1. Install dependencies

```bash
npm install
```

## 2. Supabase

1. Buat project Supabase (atau pakai yang sudah ada — lihat `supabase.md`).
2. Buka `SQL Editor` di dashboard Supabase, paste isi
   `supabase/migrations/001_init_registrations.sql`, lalu Run.
   - Ini bikin tabel `registrations` + `event_settings` (quota default 150),
     function `submit_registration` (anti-dobel-submit + quota, atomic) dan
     `get_event_stats`.
   - Aman dijalankan ulang (`if not exists` / `on conflict do nothing`).
3. Ambil `Project URL` dan `anon public key` dari `Settings > API`.

## 3. Environment variables

Buat `.env.local` dari `.env.example`:

```
VITE_SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
VITE_SUPABASE_ANON_KEY=xxxxxxxxxxxx
VITE_ADMIN_PASSWORD=pilih-password-sendiri
```

`VITE_ADMIN_PASSWORD` cuma password sederhana untuk buka `/admin` (lihat
jumlah confirmed vs waitlist) — bukan auth yang secure, tapi cukup untuk
kebutuhan ini karena `get_event_stats` memang sudah anon-executable.

```bash
npm run dev
```

Isi form RSVP, cek tabel `registrations` di Supabase — baris harus masuk.
Buka `/admin`, masukkan password, lihat angka confirmed/waitlist/quota.

## 4. Deploy ke Vercel

```bash
npm i -g vercel
vercel
```

Atau push ke GitHub lalu import di dashboard Vercel (auto-detect Vite).

**Penting:** tambahkan `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, dan
`VITE_ADMIN_PASSWORD` di Vercel `Settings > Environment Variables`, lalu
redeploy — variabel di `.env.local` tidak ikut ter-upload.

`vercel.json` sudah menangani SPA fallback (`/admin` tidak 404 saat direfresh).

## 5. Custom domain

Di Vercel `Settings > Domains`, tambahkan domain event. Vercel kasih CNAME,
masukkan ke DNS. Tunggu propagasi, pastikan `https://` sudah hijau sebelum
broadcast link ke WhatsApp.

## 6. Konten & kuota

- Deskripsi acara, cover, lineup, dll diedit lewat `public/content.md`
  (langsung refresh, tidak perlu rebuild).
- Kuota kursi (150) diatur di kolom `event_settings.quota` di Supabase —
  **bukan** di `content.md`. Ubah lewat SQL Editor kalau perlu:
  `update event_settings set quota = 200 where id = 1;`

## Yang perlu dicek sebelum broadcast

- [ ] Jalankan migration di project Supabase yang benar (production, bukan test)
- [ ] `VITE_ADMIN_PASSWORD` sudah diset di Vercel (bukan cuma di `.env.local`)
- [ ] Halaman sudah live di domain final sebelum link dibroadcast
- [ ] Tes submit 1x nomor asli, cek masuk sebagai `confirmed` di `/admin`
- [ ] Tes submit nomor yang sama lagi → harus dapat pesan "already registered"
