-- Anti-double-submit only covered phone_normalized — someone could resubmit
-- with a different name/phone but the same email and get a second confirmed
-- slot. Add a normalized+unique email column and check it in submit_registration
-- the same way phone already is (single insert, unique_violation on either
-- column rolls back atomically and returns 'already_registered').

-- IMPORTANT: run this BEFORE the migration, if you have test data with
-- duplicate emails already (the ALTER at the bottom will fail otherwise).
-- Inspect duplicates:
--   select email, count(*) from registrations group by email having count(*) > 1;
-- Then delete the rows you don't want to keep, e.g.:
--   delete from registrations where id = '<uuid-of-the-row-to-remove>';

alter table registrations add column if not exists email_normalized text;

update registrations
set email_normalized = lower(trim(email))
where email_normalized is null and email is not null and trim(email) <> '';

alter table registrations
  add constraint registrations_email_normalized_key unique (email_normalized);

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

  v_status := case when v_new_count is null then 'waitlist' else 'confirmed' end;

  begin
    insert into registrations(name, phone, phone_normalized, email, email_normalized, member, guest_count, notes, status)
    values (p_name, p_phone, v_phone_norm, p_email, v_email_norm, p_member, p_guest_count, p_notes, v_status);
  exception when unique_violation then
    if v_status = 'confirmed' then
      update event_settings set confirmed_count = confirmed_count - 1;
    end if;
    return json_build_object('success', false, 'error', 'already_registered');
  end;

  return json_build_object('success', true, 'status', v_status);
end; $$;
