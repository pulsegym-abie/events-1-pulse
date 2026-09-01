// Soft client-side check for the national number typed next to the country-code
// dropdown (CountryCodeSelect) — just enough digits to catch typos before
// submitting. The authoritative check (and the normalization used for
// anti-double-submit) lives in the `normalize_phone` Postgres function.
export function isValidPhoneNumber(raw) {
  const digits = String(raw || '').replace(/\D/g, '')
  return digits.length >= 6 && digits.length <= 14
}
