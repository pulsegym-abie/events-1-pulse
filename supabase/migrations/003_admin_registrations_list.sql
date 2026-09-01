-- Admin needs to see the actual registrant list (name/phone/email/status), not
-- just aggregate counts. That's more sensitive than get_event_stats (which only
-- returns numbers and is meant to be publicly callable from the main RSVP page),
-- so this one is gated by a real server-side password check inside the function
-- itself — the /admin page's client-side password screen alone would NOT stop
-- someone from calling the RPC directly with just the anon key.

create table if not exists admin_config (
  id int primary key default 1,
  password text not null
);
-- No default row is inserted here on purpose (a password shouldn't ship in a
-- committed migration). After running this, set yours — use the same value as
-- VITE_ADMIN_PASSWORD:
--   insert into admin_config (id, password) values (1, 'your-password-here')
--   on conflict (id) do update set password = excluded.password;

create or replace function get_registrations(p_password text)
returns setof registrations
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from admin_config where id = 1 and password = p_password) then
    raise exception 'unauthorized';
  end if;
  return query select * from registrations order by created_at desc;
end; $$;

alter table admin_config enable row level security;
-- sengaja tidak ada policy select/insert untuk anon di tabel ini —
-- satu-satunya akses yang diizinkan lewat password check di dalam function di atas
grant execute on function get_registrations to anon;
