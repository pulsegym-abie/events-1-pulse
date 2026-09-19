-- Tambah kolom Instagram opsional di form RSVP, supaya admin bisa langsung
-- buka profil IG tamu dari /admin (tombol quick-link, sama pola dengan
-- tombol WA yang sudah ada). Tidak ada unique constraint di sini — beda
-- dari phone/email, Instagram cuma info tambahan, bukan kunci anti-dobel-submit.

alter table registrations add column if not exists instagram text;

-- `create or replace` only overwrites a function with the EXACT SAME
-- parameter signature. p_instagram was inserted in the middle of the
-- argument list (not appended), so without this drop, Postgres would keep
-- the old 6-arg version around as a separate overload alongside the new
-- 7-arg one — two functions named submit_registration, which is exactly
-- the "function name is not unique" error the plain GRANT below would hit.
drop function if exists submit_registration(text, text, text, text, int, text);

create or replace function submit_registration(
  p_name text,
  p_phone text,
  p_email text default null,
  p_instagram text default null,
  p_member text default null,
  p_guest_count int default 1,
  p_notes text default null
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone_norm text := normalize_phone(p_phone);
  v_email_norm text := nullif(lower(trim(p_email)), '');
  -- Terima input bebas: "@handle", "instagram.com/handle",
  -- "https://www.instagram.com/handle/?igsh=..." — semua diringkas jadi
  -- "handle" polos supaya link wa.me-style (instagram.com/<handle>) di
  -- admin selalu valid.
  v_instagram_norm text := nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(trim(p_instagram), '^(https?://)?(www\.)?instagram\.com/', '', 'i'),
        '^@', ''
      ),
      '[/?].*$', ''
    ),
    ''
  );
  v_new_count int;
  v_status text;
begin
  update event_settings set confirmed_count = confirmed_count + 1
  where confirmed_count < quota
  returning confirmed_count into v_new_count;

  v_status := case when v_new_count is null then 'waitlist' else 'pending' end;

  begin
    insert into registrations(name, phone, phone_normalized, email, email_normalized, instagram, member, guest_count, notes, status)
    values (p_name, p_phone, v_phone_norm, p_email, v_email_norm, v_instagram_norm, p_member, p_guest_count, p_notes, v_status);
  exception when unique_violation then
    if v_status = 'pending' then
      update event_settings set confirmed_count = confirmed_count - 1;
    end if;
    return json_build_object('success', false, 'error', 'already_registered');
  end;

  return json_build_object('success', true, 'status', v_status);
end; $$;

grant execute on function submit_registration to anon;
