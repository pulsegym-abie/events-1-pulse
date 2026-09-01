-- One-off fix: confirmed_count drifted from reality because test rows were
-- deleted directly in Table Editor instead of through submit_registration
-- (the only place that keeps the counter in sync). Recompute it from the
-- actual data. Safe to run any time confirmed_count looks wrong.
update event_settings
set confirmed_count = (select count(*) from registrations where status = 'confirmed')
where id = 1;
