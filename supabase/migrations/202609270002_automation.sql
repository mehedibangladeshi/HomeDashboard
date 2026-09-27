create table public.calendar_outbox (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('household_event', 'chore_occurrence', 'obligation_occurrence')),
  entity_id uuid not null,
  operation text not null check (operation in ('upsert', 'delete')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  unique (household_id, entity_type, entity_id)
);

create table public.google_oauth_states (
  state_hash text primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.calendar_outbox enable row level security;
alter table public.google_oauth_states enable row level security;

create or replace function public.queue_calendar_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  target_id uuid;
  target_household uuid;
  target_type text;
  target_operation text;
begin
  target_id := coalesce(new.id, old.id);
  target_household := coalesce(new.household_id, old.household_id);
  target_type := case tg_table_name
    when 'household_events' then 'household_event'
    when 'chore_occurrences' then 'chore_occurrence'
    when 'obligation_occurrences' then 'obligation_occurrence'
  end;
  target_operation := case when tg_op = 'DELETE' then 'delete' else 'upsert' end;
  insert into public.calendar_outbox (household_id, entity_type, entity_id, operation)
  values (target_household, target_type, target_id, target_operation)
  on conflict (household_id, entity_type, entity_id) do update
    set operation = excluded.operation, attempts = 0, available_at = now(), last_error = null;
  return coalesce(new, old);
end;
$$;

create trigger household_events_calendar_outbox
after insert or update or delete on public.household_events
for each row execute function public.queue_calendar_change();
create trigger chore_occurrences_calendar_outbox
after insert or update or delete on public.chore_occurrences
for each row execute function public.queue_calendar_change();
create trigger obligation_occurrences_calendar_outbox
after insert or update or delete on public.obligation_occurrences
for each row execute function public.queue_calendar_change();

create or replace function public.materialize_due_notifications(p_until timestamptz default now() + interval '5 minutes')
returns integer language plpgsql security definer set search_path = '' as $$
declare
  inserted_count integer := 0;
  batch_count integer := 0;
begin
  insert into public.notifications (household_id, user_id, dedupe_key, title, body, scheduled_for)
  select c.household_id, c.assignee_user_id,
    'chore:' || c.id || ':' || r.minutes_before,
    'Chore reminder', c.title_snapshot,
    c.due_at - make_interval(mins => r.minutes_before)
  from public.chore_occurrences c
  join public.reminder_rules r on r.household_id = c.household_id
    and r.entity_type = 'chore' and r.enabled
  where c.status = 'scheduled'
    and c.due_at - make_interval(mins => r.minutes_before) <= p_until
    and c.due_at >= now() - interval '1 day'
  on conflict (user_id, dedupe_key) do nothing;
  get diagnostics inserted_count = row_count;

  insert into public.notifications (household_id, user_id, dedupe_key, title, body, scheduled_for)
  select o.household_id, m.user_id,
    'obligation:' || o.id || ':' || r.minutes_before,
    'Payment due', o.title_snapshot,
    o.due_at - make_interval(mins => r.minutes_before)
  from public.obligation_occurrences o
  join public.reminder_rules r on r.household_id = o.household_id
    and r.entity_type = 'obligation' and r.enabled
  join public.memberships m on m.household_id = o.household_id and m.role in ('owner', 'manager')
  where o.status = 'scheduled'
    and o.due_at - make_interval(mins => r.minutes_before) <= p_until
    and o.due_at >= now() - interval '3 days'
  on conflict (user_id, dedupe_key) do nothing;
  get diagnostics batch_count = row_count;
  inserted_count := inserted_count + batch_count;

  insert into public.notifications (household_id, user_id, dedupe_key, title, body, scheduled_for)
  select e.household_id, m.user_id,
    'event:' || e.id || ':' || r.minutes_before,
    'Family event', e.title,
    e.starts_at - make_interval(mins => r.minutes_before)
  from public.household_events e
  join public.reminder_rules r on r.household_id = e.household_id
    and r.entity_type = 'event' and r.enabled
  join public.memberships m on m.household_id = e.household_id
  where e.status = 'scheduled'
    and e.starts_at - make_interval(mins => r.minutes_before) <= p_until
    and e.starts_at >= now() - interval '1 day'
  on conflict (user_id, dedupe_key) do nothing;
  get diagnostics batch_count = row_count;
  inserted_count := inserted_count + batch_count;
  return inserted_count;
end;
$$;

create or replace function public.mark_household_for_deletion(p_household_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_household_owner(p_household_id) then raise exception 'Owner access required'; end if;
  update public.households set deleted_at = now(), purge_after = now() + interval '30 days', updated_at = now()
  where id = p_household_id and deleted_at is null;
  insert into public.audit_events (household_id, actor_user_id, action, entity_type, entity_id)
  values (p_household_id, auth.uid(), 'deletion_scheduled', 'household', p_household_id);
end;
$$;

create or replace function public.restore_household(p_household_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_household_owner(p_household_id) then raise exception 'Owner access required'; end if;
  update public.households set deleted_at = null, purge_after = null, updated_at = now()
  where id = p_household_id and purge_after > now();
end;
$$;

create or replace function public.purge_expired_households()
returns integer language plpgsql security definer set search_path = '' as $$
declare deleted_count integer;
begin
  delete from public.households where purge_after is not null and purge_after <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.mark_household_for_deletion(uuid) to authenticated;
grant execute on function public.restore_household(uuid) to authenticated;

select cron.schedule(
  'materialize-home-reminders',
  '*/5 * * * *',
  $$select public.materialize_due_notifications();$$
);
select cron.schedule(
  'purge-expired-households',
  '17 3 * * *',
  $$select public.purge_expired_households();$$
);
