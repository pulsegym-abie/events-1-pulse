# Pulse Powerhub RSVP — Setup

## 1. Install dependencies

```bash
npm install
```

## 2. Supabase

1. Buat project Supabase (atau pakai yang sudah ada — lihat `supabase.md`).
2. Buka `SQL Editor` di dashboard Supabase, jalankan migration di
   `supabase/migrations/` **berurutan** (001, 002, 003):
   - `001_init_registrations.sql` — tabel `registrations` + `event_settings`
     (quota default 150), function `submit_registration` (anti-dobel-submit +
     quota, atomic) dan `get_event_stats`.
   - `002_normalize_phone_international.sql` — perbaikan normalisasi nomor
     untuk tamu internasional (bukan cuma nomor Indonesia).
   - `003_admin_registrations_list.sql` — tabel `admin_config` + function
     `get_registrations` (list registrant untuk `/admin`, dicek password
     server-side). Setelah run, isi passwordnya (samakan dengan
     `VITE_ADMIN_PASSWORD`):
     ```sql
     insert into admin_config (id, password) values (1, 'password-yang-sama-dengan-VITE_ADMIN_PASSWORD')
     on conflict (id) do update set password = excluded.password;
     ```
   - `004_email_anti_duplicate.sql` — tambah unique check di email, bukan
     cuma nomor telepon.
   - `006_manual_admin_approval.sql` — submit RSVP sekarang masuk sebagai
     `pending` (bukan langsung `confirmed`), admin approve/decline manual
     satu-satu dari `/admin` (function `approve_registration`,
     `decline_registration`, `get_admin_stats`). Kuota tetap dipotong atomic
     saat submit (sama seperti sebelumnya) — approve/decline cuma lapisan
     verifikasi di atasnya, bukan penentu kuota.
   - Semua migration aman dijalankan ulang (`if not exists` / `create or replace`).
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
Buka `/admin`, masukkan password, lihat angka confirmed/waitlist/quota plus
daftar registrant (nama/telp/email) — bisa di-export CSV (buka langsung di
Excel) atau Print/PDF.

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
- [ ] Tes submit 1x nomor asli, cek masuk sebagai `pending` di `/admin`
- [ ] Tes submit nomor yang sama lagi → harus dapat pesan "already registered"
- [ ] Tes tombol Confirm/Decline di `/admin`, pastikan `confirmed_count` tetap
      benar di kedua kasus (Confirm tidak mengubah, Decline mengurangi 1)
