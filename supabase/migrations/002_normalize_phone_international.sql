-- The frontend now sends phone numbers as country-dial-code + national number,
-- picked from an explicit country dropdown (not just Indonesian numbers with a
-- guessed prefix). The original normalize_phone() heuristic force-prefixed
-- "62" onto anything that didn't already start with "62" or "0", which would
-- corrupt a real foreign number like "+61 412 345 678" into "6261412345678".
-- Since the dial code is now always explicit in the input, normalization is
-- just "strip everything but digits" — no guessing needed.
create or replace function normalize_phone(p_phone text) returns text
language plpgsql immutable as $$
begin
  return regexp_replace(p_phone, '[^0-9]', '', 'g');
end; $$;
