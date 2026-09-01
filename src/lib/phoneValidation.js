// Soft client-side check for Indonesian WhatsApp numbers, so people get instant
// feedback before submitting. The authoritative check (and the normalization used
// for anti-double-submit) lives in the `normalize_phone` Postgres function.
export function isValidIndonesianPhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '')
  const normalized = digits.startsWith('62')
    ? digits
    : digits.startsWith('0')
      ? '62' + digits.slice(1)
      : '62' + digits

  // Indonesian mobiles: 62 8xx followed by 7-10 more digits (10-13 digits total after 62).
  return /^628\d{7,10}$/.test(normalized)
}
