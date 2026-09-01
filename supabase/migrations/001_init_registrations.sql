-- Event RSVP: registrations table, quota/waitlist counter, and the two RPCs
-- the frontend calls (submit_registration, get_event_stats). All quota /
-- anti-double-submit logic lives here so it stays atomic under concurrent
-- submissions — the client never inserts into `registrations` directly.

create table if not exists registrations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  phone_normalized text unique not null,
  email text,
  member text check (member in ('yes', 'no')),
  guest_count int default 1,
  notes text,
  status text not null default 'confirmed' check (status in ('confirmed', 'waitlist')),
  created_at timestamptz default now()
);

create table if not exists event_settings (
  id int primary key default 1,
  quota int not null default 150,
  confirmed_count int not null default 0
);
insert into event_settings (id, quota, confirmed_count)
values (1, 150, 0)
on conflict (id) do nothing;

create or replace function normalize_phone(p_phone text) returns text
language plpgsql immutable as $$
declare v text;
begin
  v := regexp_replace(p_phone, '[^0-9]', '', 'g');
  if left(v, 2) = '62' then return v;
  elsif left(v, 1) = '0' then return '62' || substring(v from 2);
  else return '62' || v;
  end if;
end; $$;

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
  v_new_count int;
  v_status text;
begin
  update event_settings set confirmed_count = confirmed_count + 1
  where confirmed_count < quota
  returning confirmed_count into v_new_count;

  v_status := case when v_new_count is null then 'waitlist' else 'confirmed' end;

  begin
    insert into registrations(name, phone, phone_normalized, email, member, guest_count, notes, status)
    values (p_name, p_phone, v_phone_norm, p_email, p_member, p_guest_count, p_notes, v_status);
  exception when unique_violation then
    if v_status = 'confirmed' then
      update event_settings set confirmed_count = confirmed_count - 1;
    end if;
    return json_build_object('success', false, 'error', 'already_registered');
  end;

  return json_build_object('success', true, 'status', v_status);
end; $$;

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

alter table registrations enable row level security;
alter table event_settings enable row level security;
-- sengaja tidak ada policy select/insert untuk anon di kedua tabel ini —
-- satu-satunya akses yang diizinkan lewat function di atas
grant execute on function submit_registration to anon;
grant execute on function get_event_stats to anon;
