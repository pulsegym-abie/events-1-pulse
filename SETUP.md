# Pulse Powerhub RSVP — Setup

## 1. Install Vue 3

```bash
npm create vite@latest pulse-rsvp -- --template vue
cd pulse-rsvp
npm install
```

Tidak ada dependency tambahan. Form pakai `fetch` bawaan browser.

Lalu timpa file hasil scaffold dengan file dari sini:

```
pulse-rsvp/
├── index.html          ← ganti
├── src/
│   ├── App.vue         ← ganti
│   └── main.js         ← ganti
├── Code.gs             ← ini untuk Apps Script, bukan bagian build
└── .env.local          ← buat sendiri dari .env.example
```

Hapus `src/components/HelloWorld.vue` dan `src/style.css` bawaan Vite.

## 2. Google Sheets

1. Buat Sheet baru, rename tab pertama jadi **RSVP**
2. `Extensions > Apps Script`, hapus isinya, paste `Code.gs`
3. Jalankan fungsi `setupSheet` sekali (klik Run, izinkan permission)
4. `Deploy > New deployment > Web app`
   - Execute as: **Me**
   - Who has access: **Anyone**
5. Copy URL yang berakhiran `/exec`

Tes dulu: buka URL `/exec` di browser. Harus muncul `{"status":"ok",...}`.

## 3. Hubungkan frontend

Buat file `.env.local`:

```
VITE_SHEETS_ENDPOINT=https://script.google.com/macros/s/XXXX/exec
```

```bash
npm run dev
```

Submit form, cek Sheet — baris harus masuk.

## 4. Deploy ke Vercel

```bash
npm i -g vercel
vercel
```

Atau push ke GitHub lalu import di dashboard Vercel (auto-detect Vite).

**Penting:** tambahkan `VITE_SHEETS_ENDPOINT` di Vercel
`Settings > Environment Variables`, lalu redeploy. Variabel di `.env.local`
tidak ikut ter-upload.

## 5. Custom domain

Di Vercel `Settings > Domains`, tambahkan `app.pulsepowerhub.com`.
Vercel kasih CNAME, masukkan ke DNS. Tunggu propagasi, pastikan
`https://` sudah hijau sebelum submit template ke Meta.

## 6. Tracking channel

Karena pakai Static URL di template WhatsApp, tracking per-member tidak ada.
Tapi kamu tetap bisa tahu channel mana yang jalan, dengan query param:

- Tombol WhatsApp → `https://app.pulsepowerhub.com/?src=wa`
- Link di email   → `https://app.pulsepowerhub.com/?src=email`
- Bio Instagram   → `https://app.pulsepowerhub.com/?src=ig`

Nilainya otomatis masuk kolom **Source** di Sheet.

## Yang perlu dicek sebelum blast

- [ ] Jam event: flyer bilang 5–8 PM, template WA bilang "until late" — samakan
- [ ] Domain: pitch deck pakai pulsepowerhub.id, template pakai app.pulsepowerhub.com
- [ ] Kapasitas: target deck 150 guests, blast ke 600 kontak — siapkan cutoff
- [ ] Halaman sudah live sebelum submit template (reviewer Meta membukanya)
- [ ] Taruh `og.jpg` (1200×630, crop dari flyer) di folder `public/`
