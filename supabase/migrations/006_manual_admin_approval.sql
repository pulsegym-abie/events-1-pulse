-- Partiful-style manual admin approval. Until now, submit_registration
-- auto-confirmed anyone who beat the quota. From this migration on, a
-- reserved slot lands as 'pending' (still atomically reserved out of the
-- 150 quota — confirmed_count is unchanged in meaning, it's still "reserved
-- seats") and only becomes 'confirmed' after an admin manually approves it
-- via approve_registration(). Declining/revoking frees the seat back up by
-- decrementing confirmed_count, mirroring the existing unique_violation
-- rollback pattern below.
--
-- Status lifecycle after this migration:
--   pending    -> reserved seat, awaiting admin review (new)
--   confirmed  -> admin-approved (meaning changed: was "auto", now "manual")
--   waitlist   -> unchanged, no seat reserved
--   declined   -> admin rejected/revoked a pending or confirmed row (new).
--                 Row is KEPT (not deleted) so phone/email uniqueness still
--                 blocks a spam re-submit, and so it stays visible/exportable
--                 in /admin for audit purposes.
--
-- No data backfill needed: existing status='confirmed' rows already count
-- as "approved" under the new meaning, so they're left exactly as-is.

-- 1. Widen the status check constraint. Find the constraint dynamically
--    instead of hardcoding its (default-generated) name, in case it was
--    ever created differently than Postgres's usual <table>_<col>_check.
do $$
declare
  v_conname text;
begin
  select conname into v_conname
  from pg_constraint
  where conrelid = 'registrations'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%status%';

  if v_conname is not null then
    execute format('alter table registrations drop constraint %I', v_conname);
  end if;
end $$;

alter table registrations
  add constraint registrations_status_check
  check (status in ('pending', 'confirmed', 'waitlist', 'declined'));

-- 2. submit_registration: identical atomic quota logic, only the label for
--    "got a slot" changes from 'confirmed' to 'pending'.
create or replace function submit_registration(
  p_name text,
  p_phone text,
  p_email text default null,
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
  v_new_count int;
  v_status text;
begin
  update event_settings set confirmed_count = confirmed_count + 1
  where confirmed_count < quota
  returning confirmed_count into v_new_count;

  -- 'pending', bukan 'confirmed' lagi — kursi sudah direservasi
  -- (confirmed_count naik), tapi baru resmi 'confirmed' setelah admin
  -- approve manual lewat approve_registration(). confirmed_count tetap
  -- berarti "reserved seats" (pending + confirmed) supaya math kuota
  -- publik di get_event_stats() tidak berubah sama sekali.
  v_status := case when v_new_count is null then 'waitlist' else 'pending' end;

  begin
    insert into registrations(name, phone, phone_normalized, email, email_normalized, member, guest_count, notes, status)
    values (p_name, p_phone, v_phone_norm, p_email, v_email_norm, p_member, p_guest_count, p_notes, v_status);
  exception when unique_violation then
    if v_status = 'pending' then
      update event_settings set confirmed_count = confirmed_count - 1;
    end if;
    return json_build_object('success', false, 'error', 'already_registered');
  end;

  return json_build_object('success', true, 'status', v_status);
end; $$;

-- 3. get_event_stats(): UNCHANGED on purpose — confirmed_count already means
--    "reserved seats" both before and after this migration, so the public
--    RSVP page's spots-left math needs zero frontend changes. Re-declared
--    here only so this migration file is a complete, standalone record —
--    the body is byte-identical to 004/001.
create or replace function get_event_stats() returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'quota', quota,
    'confirmed_count', confirmed_count,
    'waitlist_count', (select count(*) from registrations where status = 'waitlist')
  ) from event_settings;
$$;

-- 4. Admin-only breakdown stats — separate from get_event_stats() so the
--    public, anon-hit-every-pageload function's contract never has to move.
--    NOTE naming: 'approved_count' here is NOT the same thing as
--    get_event_stats().confirmed_count ("reserved") — deliberately different
--    key name to avoid two RPCs using "confirmed_count" to mean two things.
create or replace function get_admin_stats(p_password text) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result json;
begin
  if not exists (select 1 from admin_config where id = 1 and password = p_password) then
    raise exception 'unauthorized';
  end if;

  select json_build_object(
    'quota', es.quota,
    'reserved_count', es.confirmed_count,
    'approved_count', (select count(*) from registrations where status = 'confirmed'),
    'pending_count', (select count(*) from registrations where status = 'pending'),
    'waitlist_count', (select count(*) from registrations where status = 'waitlist'),
    'declined_count', (select count(*) from registrations where status = 'declined')
  ) into v_result
  from event_settings es where es.id = 1;

  return v_result;
end; $$;

-- 5. Approve: pending -> confirmed. Does NOT touch confirmed_count — the
--    seat was already reserved at submit time, approving just relabels it.
create or replace function approve_registration(p_password text, p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not exists (select 1 from admin_config where id = 1 and password = p_password) then
    raise exception 'unauthorized';
  end if;

  update registrations set status = 'confirmed'
  where id = p_id and status = 'pending'
  returning status into v_status;

  if v_status is null then
    return json_build_object('success', false, 'error', 'not_pending');
  end if;

  return json_build_object('success', true, 'status', 'confirmed');
end; $$;

-- 6. Decline (also doubles as "revoke" for an already-confirmed row): frees
--    the reserved seat by decrementing confirmed_count. The WHERE clause
--    (status in ('pending','confirmed')) plus RETURNING is what makes this
--    safe under a double-click or a concurrent admin action on the same
--    row — the second call's UPDATE matches zero rows (status is already
--    'declined'), v_prev_status stays null, and the counter decrement is
--    skipped. Mirrors the unique_violation rollback in submit_registration.
create or replace function decline_registration(p_password text, p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev_status text;
begin
  if not exists (select 1 from admin_config where id = 1 and password = p_password) then
    raise exception 'unauthorized';
  end if;

  update registrations set status = 'declined'
  where id = p_id and status in ('pending', 'confirmed')
  returning status into v_prev_status;

  if v_prev_status is null then
    return json_build_object('success', false, 'error', 'not_active');
  end if;

  update event_settings set confirmed_count = greatest(confirmed_count - 1, 0)
  where id = 1;

  return json_build_object('success', true, 'status', 'declined');
end; $$;

grant execute on function get_admin_stats to anon;
grant execute on function approve_registration to anon;
grant execute on function decline_registration to anon;
-- submit_registration / get_event_stats already granted in 001, re-grant is
-- harmless if this migration is ever re-run.
grant execute on function submit_registration to anon;
grant execute on function get_event_stats to anon;
