create extension if not exists pgcrypto;
create extension if not exists citext;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create type public.household_role as enum ('owner', 'manager', 'member');
create type public.expense_status as enum ('pending', 'approved', 'rejected', 'voided');
create type public.expense_kind as enum ('purchase', 'obligation_payment', 'other');
create type public.recurrence_frequency as enum ('once', 'daily', 'weekdays', 'weekly', 'monthly');
create type public.occurrence_status as enum ('scheduled', 'completed', 'cancelled');
create type public.notification_status as enum ('pending', 'delivered', 'read', 'failed');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text,
  quiet_hours_start time,
  quiet_hours_end time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 80),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  time_zone text not null default 'UTC',
  week_starts_on smallint not null default 1 check (week_starts_on = 1),
  deleted_at timestamptz,
  purge_after timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.household_role not null,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id),
  unique (user_id)
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  email citext not null,
  role public.household_role not null default 'member',
  token_hash text not null unique,
  invited_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 60),
  parent_id uuid references public.categories(id),
  color integer,
  icon text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (household_id, name)
);

create table public.payment_sources (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 60),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (household_id, name)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  client_mutation_id uuid not null,
  kind public.expense_kind not null default 'purchase',
  status public.expense_status not null,
  summary text not null check (length(trim(summary)) between 1 and 160),
  total_minor bigint not null check (total_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  incurred_at timestamptz not null,
  payer_user_id uuid not null references auth.users(id),
  category_id uuid references public.categories(id),
  payment_source_id uuid references public.payment_sources(id),
  note text check (length(note) <= 2000),
  receipt_path text,
  submitted_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_reason text,
  correction_reason text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, client_mutation_id)
);

create table public.expense_items (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  amount_minor bigint not null,
  category_id uuid references public.categories(id),
  sort_order integer not null default 0
);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  category_id uuid not null references public.categories(id),
  month_start date not null check (extract(day from month_start) = 1),
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, category_id, month_start)
);

create table public.obligations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 120),
  expected_amount_minor bigint check (expected_amount_minor > 0),
  category_id uuid references public.categories(id),
  frequency public.recurrence_frequency not null,
  starts_on date not null,
  due_time time not null default '09:00',
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.obligation_occurrences (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  obligation_id uuid not null references public.obligations(id) on delete cascade,
  title_snapshot text not null,
  due_at timestamptz not null,
  status public.occurrence_status not null default 'scheduled',
  expense_id uuid references public.expenses(id),
  calendar_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (obligation_id, due_at)
);

create table public.chores (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 120),
  description text check (length(description) <= 2000),
  assignee_user_id uuid not null references auth.users(id),
  frequency public.recurrence_frequency not null default 'once',
  starts_at timestamptz not null,
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chore_occurrences (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  chore_id uuid not null references public.chores(id) on delete cascade,
  title_snapshot text not null,
  assignee_user_id uuid not null references auth.users(id),
  due_at timestamptz not null,
  status public.occurrence_status not null default 'scheduled',
  completed_at timestamptz,
  completed_by uuid references auth.users(id),
  calendar_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (chore_id, due_at)
);

create table public.household_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  description text check (length(description) <= 4000),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  all_day boolean not null default false,
  status public.occurrence_status not null default 'scheduled',
  calendar_event_id text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.calendar_connections (
  household_id uuid primary key references public.households(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id),
  google_calendar_id text not null,
  encrypted_refresh_token text not null,
  sync_token text,
  channel_id text,
  channel_resource_id text,
  channel_expires_at timestamptz,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.calendar_mappings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('household_event', 'chore_occurrence', 'obligation_occurrence')),
  entity_id uuid not null,
  google_event_id text not null,
  google_etag text,
  last_origin text not null check (last_origin in ('app', 'google')),
  last_synced_at timestamptz not null default now(),
  unique (household_id, entity_type, entity_id),
  unique (household_id, google_event_id)
);

create table public.reminder_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('obligation', 'chore', 'event')),
  entity_id uuid,
  minutes_before integer not null check (minutes_before >= 0),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  unique nulls not distinct (household_id, entity_type, entity_id, minutes_before)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  dedupe_key text not null,
  title text not null,
  body text not null,
  scheduled_for timestamptz not null,
  status public.notification_status not null default 'pending',
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, dedupe_key)
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  actor_source text not null default 'app',
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index expenses_household_date_idx on public.expenses (household_id, incurred_at desc);
create index expenses_household_status_idx on public.expenses (household_id, status);
create index chore_occurrences_due_idx on public.chore_occurrences (household_id, due_at) where status = 'scheduled';
create index obligation_occurrences_due_idx on public.obligation_occurrences (household_id, due_at) where status = 'scheduled';
create index notifications_dispatch_idx on public.notifications (scheduled_for) where status = 'pending';

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  invite_token text;
  invite_row public.invitations;
begin
  insert into public.profiles (user_id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1), ''),
    new.raw_user_meta_data ->> 'avatar_url'
  );
  invite_token := new.raw_user_meta_data ->> 'household_invite_token';
  if invite_token is not null then
    select * into invite_row from public.invitations
    where token_hash = encode(extensions.digest(invite_token, 'sha256'), 'hex')
      and lower(email::text) = lower(new.email)
      and accepted_at is null and expires_at > now()
    for update;
    if invite_row.id is not null then
      insert into public.memberships (household_id, user_id, role)
      values (invite_row.household_id, new.id, invite_row.role);
      update public.invitations set accepted_at = now() where id = invite_row.id;
    end if;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.household_role_for(p_household_id uuid)
returns public.household_role language sql stable security definer set search_path = '' as $$
  select role from public.memberships
  where household_id = p_household_id and user_id = auth.uid();
$$;

create or replace function public.is_household_member(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships
    where household_id = p_household_id and user_id = auth.uid()
  );
$$;

create or replace function public.can_operate_household(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.household_role_for(p_household_id) in ('owner', 'manager'), false);
$$;

create or replace function public.is_household_owner(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.household_role_for(p_household_id) = 'owner', false);
$$;

create view public.my_households with (security_invoker = true) as
select h.id, h.name, h.currency_code, h.time_zone, m.role
from public.households h
join public.memberships m on m.household_id = h.id
where m.user_id = auth.uid() and h.deleted_at is null;

create or replace function public.create_household(
  household_name text,
  currency text,
  timezone text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists (select 1 from public.memberships where user_id = auth.uid()) then
    raise exception 'A user may belong to only one household';
  end if;
  insert into public.households (name, currency_code, time_zone, created_by)
  values (trim(household_name), upper(currency), timezone, auth.uid()) returning id into new_id;
  insert into public.memberships (household_id, user_id, role)
  values (new_id, auth.uid(), 'owner');
  insert into public.categories (household_id, name, icon) values
    (new_id, 'Groceries', 'shopping_cart'),
    (new_id, 'Household', 'home'),
    (new_id, 'Personal', 'person'),
    (new_id, 'Rent', 'key'),
    (new_id, 'Utilities', 'bolt'),
    (new_id, 'Transport', 'directions_car'),
    (new_id, 'Other', 'category');
  insert into public.payment_sources (household_id, name) values
    (new_id, 'Cash'), (new_id, 'Card'), (new_id, 'Bank'), (new_id, 'Mobile wallet');
  insert into public.reminder_rules (household_id, entity_type, minutes_before) values
    (new_id, 'obligation', 4320), (new_id, 'obligation', 540),
    (new_id, 'chore', 1440), (new_id, 'chore', 0),
    (new_id, 'event', 1440), (new_id, 'event', 60);
  return new_id;
end;
$$;

create or replace function public.create_purchase(
  p_client_mutation_id uuid,
  p_household_id uuid,
  p_summary text,
  p_total_minor bigint,
  p_currency_code text,
  p_incurred_at timestamptz,
  p_payer_user_id uuid,
  p_category_id uuid,
  p_payment_source_id uuid,
  p_note text,
  p_items jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
  member_role public.household_role;
  item jsonb;
  item_total bigint;
  expected_currency text;
begin
  member_role := public.household_role_for(p_household_id);
  if member_role is null then raise exception 'Not a household member'; end if;
  if member_role = 'member' and p_payer_user_id <> auth.uid() then
    raise exception 'Members may submit only their own spending';
  end if;
  select currency_code into expected_currency from public.households where id = p_household_id;
  if expected_currency <> upper(p_currency_code) then raise exception 'Currency mismatch'; end if;
  if p_total_minor <= 0 or jsonb_array_length(p_items) = 0 then raise exception 'Invalid purchase'; end if;
  select coalesce(sum((value ->> 'amount_minor')::bigint), 0)
    into item_total from jsonb_array_elements(p_items);
  if item_total <> p_total_minor then raise exception 'Items must reconcile with total'; end if;

  insert into public.expenses (
    household_id, client_mutation_id, kind, status, summary, total_minor,
    currency_code, incurred_at, payer_user_id, category_id, payment_source_id,
    note, submitted_by
  ) values (
    p_household_id, p_client_mutation_id, 'purchase',
    case when member_role = 'member' then 'pending'::public.expense_status else 'approved'::public.expense_status end,
    trim(p_summary), p_total_minor, upper(p_currency_code), p_incurred_at,
    p_payer_user_id, p_category_id, p_payment_source_id, p_note, auth.uid()
  )
  on conflict (household_id, client_mutation_id) do update
    set client_mutation_id = excluded.client_mutation_id
  returning id into new_id;

  if not exists (select 1 from public.expense_items where expense_id = new_id) then
    for item in select value from jsonb_array_elements(p_items) loop
      insert into public.expense_items (expense_id, name, amount_minor, category_id, sort_order)
      values (
        new_id, trim(item ->> 'name'), (item ->> 'amount_minor')::bigint,
        nullif(item ->> 'category_id', '')::uuid,
        (select count(*) from public.expense_items where expense_id = new_id)
      );
    end loop;
    insert into public.audit_events (household_id, actor_user_id, action, entity_type, entity_id, after_data)
    select p_household_id, auth.uid(), 'created', 'expense', new_id, to_jsonb(e)
    from public.expenses e where e.id = new_id;
  end if;
  return new_id;
end;
$$;

create or replace function public.review_expense(
  p_expense_id uuid,
  p_decision public.expense_status,
  p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  old_row public.expenses;
  new_row public.expenses;
begin
  select * into old_row from public.expenses where id = p_expense_id for update;
  if not public.can_operate_household(old_row.household_id) then raise exception 'Not permitted'; end if;
  if old_row.status <> 'pending' then raise exception 'Only pending submissions can be reviewed'; end if;
  if p_decision not in ('approved', 'rejected') then raise exception 'Invalid review decision'; end if;
  if p_decision = 'rejected' and nullif(trim(p_reason), '') is null then
    raise exception 'A rejection reason is required';
  end if;
  update public.expenses set status = p_decision, reviewed_by = auth.uid(),
    reviewed_at = now(), review_reason = p_reason, version = version + 1,
    updated_at = now() where id = p_expense_id returning * into new_row;
  insert into public.audit_events (
    household_id, actor_user_id, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    old_row.household_id, auth.uid(), p_decision::text, 'expense', p_expense_id,
    to_jsonb(old_row), to_jsonb(new_row), p_reason
  );
end;
$$;

create or replace function public.complete_chore(p_occurrence_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare occurrence public.chore_occurrences;
begin
  select * into occurrence from public.chore_occurrences where id = p_occurrence_id for update;
  if not public.is_household_member(occurrence.household_id) then raise exception 'Not permitted'; end if;
  if occurrence.assignee_user_id <> auth.uid() and not public.can_operate_household(occurrence.household_id) then
    raise exception 'Only the assignee or a household operator can complete this chore';
  end if;
  update public.chore_occurrences set status = 'completed', completed_at = now(),
    completed_by = auth.uid(), updated_at = now() where id = p_occurrence_id and status = 'scheduled';
end;
$$;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.memberships enable row level security;
alter table public.invitations enable row level security;
alter table public.categories enable row level security;
alter table public.payment_sources enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_items enable row level security;
alter table public.budgets enable row level security;
alter table public.obligations enable row level security;
alter table public.obligation_occurrences enable row level security;
alter table public.chores enable row level security;
alter table public.chore_occurrences enable row level security;
alter table public.household_events enable row level security;
alter table public.calendar_connections enable row level security;
alter table public.calendar_mappings enable row level security;
alter table public.reminder_rules enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_read_household on public.profiles for select using (
  user_id = auth.uid() or exists (
    select 1 from public.memberships mine join public.memberships theirs using (household_id)
    where mine.user_id = auth.uid() and theirs.user_id = profiles.user_id
  )
);
create policy profiles_update_self on public.profiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy households_read_member on public.households for select using (public.is_household_member(id));
create policy households_update_operator on public.households for update using (public.can_operate_household(id));

create policy memberships_read_member on public.memberships for select using (public.is_household_member(household_id));
create policy memberships_insert_operator on public.memberships for insert with check (
  public.can_operate_household(household_id) and
  (role = 'member' or public.is_household_owner(household_id))
);
create policy memberships_update_owner on public.memberships for update using (public.is_household_owner(household_id));
create policy memberships_delete_operator on public.memberships for delete using (
  public.can_operate_household(household_id) and
  (role = 'member' or public.is_household_owner(household_id))
);

create policy invitations_operator_all on public.invitations for all using (public.can_operate_household(household_id))
with check (public.can_operate_household(household_id) and (role = 'member' or public.is_household_owner(household_id)));

create policy categories_read_member on public.categories for select using (public.is_household_member(household_id));
create policy categories_operator_write on public.categories for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));
create policy payment_sources_read_member on public.payment_sources for select using (public.is_household_member(household_id));
create policy payment_sources_operator_write on public.payment_sources for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));

create policy expenses_finance_or_own_submission_read on public.expenses for select using (
  public.can_operate_household(household_id) or submitted_by = auth.uid()
);
create policy expense_items_finance_or_own_read on public.expense_items for select using (
  exists (select 1 from public.expenses e where e.id = expense_id and
    (public.can_operate_household(e.household_id) or e.submitted_by = auth.uid()))
);

create policy budgets_operator_all on public.budgets for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));
create policy obligations_operator_all on public.obligations for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));
create policy obligation_occurrences_member_schedule_read on public.obligation_occurrences for select using (public.is_household_member(household_id));
create policy obligation_occurrences_operator_write on public.obligation_occurrences for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));

create policy chores_member_read on public.chores for select using (public.is_household_member(household_id));
create policy chores_create on public.chores for insert with check (
  public.can_operate_household(household_id) or
  (public.is_household_member(household_id) and assignee_user_id = auth.uid() and created_by = auth.uid())
);
create policy chores_update on public.chores for update using (
  public.can_operate_household(household_id) or (assignee_user_id = auth.uid() and created_by = auth.uid())
);
create policy chores_delete on public.chores for delete using (
  public.can_operate_household(household_id) or (assignee_user_id = auth.uid() and created_by = auth.uid())
);
create policy chore_occurrences_member_read on public.chore_occurrences for select using (public.is_household_member(household_id));
create policy chore_occurrences_operator_write on public.chore_occurrences for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));

create policy household_events_member_all on public.household_events for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy calendar_connections_owner_all on public.calendar_connections for all using (public.is_household_owner(household_id)) with check (public.is_household_owner(household_id));
create policy calendar_mappings_member_read on public.calendar_mappings for select using (public.is_household_member(household_id));
create policy reminder_rules_member_read on public.reminder_rules for select using (public.is_household_member(household_id));
create policy reminder_rules_operator_write on public.reminder_rules for all using (public.can_operate_household(household_id)) with check (public.can_operate_household(household_id));

create policy notifications_own_read on public.notifications for select using (user_id = auth.uid());
create policy notifications_own_update on public.notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy device_tokens_own_all on public.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy audit_operator_read on public.audit_events for select using (public.can_operate_household(household_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy receipt_operator_read on storage.objects for select using (
  bucket_id = 'receipts' and public.can_operate_household((storage.foldername(name))[1]::uuid)
);
create policy receipt_uploader_insert on storage.objects for insert with check (
  bucket_id = 'receipts' and public.is_household_member((storage.foldername(name))[1]::uuid)
);
create policy receipt_operator_update on storage.objects for update using (
  bucket_id = 'receipts' and public.can_operate_household((storage.foldername(name))[1]::uuid)
);
create policy receipt_operator_delete on storage.objects for delete using (
  bucket_id = 'receipts' and public.can_operate_household((storage.foldername(name))[1]::uuid)
);

grant execute on function public.create_household(text, text, text) to authenticated;
grant execute on function public.create_purchase(uuid, uuid, text, bigint, text, timestamptz, uuid, uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.review_expense(uuid, public.expense_status, text) to authenticated;
grant execute on function public.complete_chore(uuid) to authenticated;
