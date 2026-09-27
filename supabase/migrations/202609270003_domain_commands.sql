create or replace function public.create_chore(
  p_household_id uuid,
  p_title text,
  p_description text,
  p_assignee_user_id uuid,
  p_frequency public.recurrence_frequency,
  p_starts_at timestamptz
) returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Not a household member'; end if;
  if not public.can_operate_household(p_household_id) and p_assignee_user_id <> auth.uid() then
    raise exception 'Members may assign chores only to themselves';
  end if;
  if not exists (select 1 from public.memberships where household_id = p_household_id and user_id = p_assignee_user_id) then
    raise exception 'Assignee is not a household member';
  end if;
  insert into public.chores (
    household_id, title, description, assignee_user_id, frequency, starts_at, created_by
  ) values (
    p_household_id, trim(p_title), p_description, p_assignee_user_id, p_frequency, p_starts_at, auth.uid()
  ) returning id into new_id;
  perform public.generate_scheduled_occurrences(p_household_id);
  return new_id;
end;
$$;

create or replace function public.create_obligation(
  p_household_id uuid,
  p_title text,
  p_expected_amount_minor bigint,
  p_category_id uuid,
  p_frequency public.recurrence_frequency,
  p_starts_on date,
  p_due_time time
) returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if not public.can_operate_household(p_household_id) then raise exception 'Operator access required'; end if;
  insert into public.obligations (
    household_id, title, expected_amount_minor, category_id, frequency,
    starts_on, due_time, created_by
  ) values (
    p_household_id, trim(p_title), p_expected_amount_minor, p_category_id,
    p_frequency, p_starts_on, p_due_time, auth.uid()
  ) returning id into new_id;
  perform public.generate_scheduled_occurrences(p_household_id);
  return new_id;
end;
$$;

create or replace function public.generate_scheduled_occurrences(p_household_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  task record;
  bill record;
  candidate timestamptz;
  local_date date;
  inserted_count integer := 0;
  batch_count integer;
begin
  for task in
    select * from public.chores
    where active and (p_household_id is null or household_id = p_household_id)
  loop
    for counter in 0..60 loop
      candidate := case task.frequency
        when 'once' then task.starts_at
        when 'daily' then task.starts_at + make_interval(days => counter)
        when 'weekdays' then task.starts_at + make_interval(days => counter)
        when 'weekly' then task.starts_at + make_interval(weeks => counter)
        when 'monthly' then task.starts_at + make_interval(months => counter)
      end;
      if task.frequency = 'once' and counter > 0 then exit; end if;
      if task.frequency = 'weekdays' and extract(isodow from candidate) > 5 then continue; end if;
      if task.frequency = 'weekly' and counter > 12 then exit; end if;
      if task.frequency = 'monthly' and counter > 3 then exit; end if;
      if candidate > now() + interval '60 days' then exit; end if;
      insert into public.chore_occurrences (
        household_id, chore_id, title_snapshot, assignee_user_id, due_at
      ) values (
        task.household_id, task.id, task.title, task.assignee_user_id, candidate
      ) on conflict (chore_id, due_at) do nothing;
      get diagnostics batch_count = row_count;
      inserted_count := inserted_count + batch_count;
    end loop;
  end loop;

  for bill in
    select o.*, h.time_zone from public.obligations o
    join public.households h on h.id = o.household_id
    where o.active and (p_household_id is null or o.household_id = p_household_id)
  loop
    for counter in 0..60 loop
      local_date := case bill.frequency
        when 'once' then bill.starts_on
        when 'daily' then bill.starts_on + counter
        when 'weekdays' then bill.starts_on + counter
        when 'weekly' then bill.starts_on + (counter * 7)
        when 'monthly' then (bill.starts_on + make_interval(months => counter))::date
      end;
      if bill.frequency = 'once' and counter > 0 then exit; end if;
      if bill.frequency = 'weekdays' and extract(isodow from local_date) > 5 then continue; end if;
      if bill.frequency = 'weekly' and counter > 12 then exit; end if;
      if bill.frequency = 'monthly' and counter > 3 then exit; end if;
      candidate := (local_date + bill.due_time) at time zone bill.time_zone;
      if candidate > now() + interval '60 days' then exit; end if;
      insert into public.obligation_occurrences (
        household_id, obligation_id, title_snapshot, due_at
      ) values (
        bill.household_id, bill.id, bill.title, candidate
      ) on conflict (obligation_id, due_at) do nothing;
      get diagnostics batch_count = row_count;
      inserted_count := inserted_count + batch_count;
    end loop;
  end loop;
  return inserted_count;
end;
$$;

create or replace function public.set_monthly_budget(
  p_household_id uuid,
  p_category_id uuid,
  p_month_start date,
  p_amount_minor bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare budget_id uuid; household_currency text;
begin
  if not public.can_operate_household(p_household_id) then raise exception 'Operator access required'; end if;
  if extract(day from p_month_start) <> 1 then raise exception 'Budget month must start on day one'; end if;
  select currency_code into household_currency from public.households where id = p_household_id;
  insert into public.budgets (household_id, category_id, month_start, amount_minor, currency_code, created_by)
  values (p_household_id, p_category_id, p_month_start, p_amount_minor, household_currency, auth.uid())
  on conflict (household_id, category_id, month_start) do update
    set amount_minor = excluded.amount_minor, updated_at = now()
  returning id into budget_id;
  return budget_id;
end;
$$;

create or replace function public.mark_obligation_paid(
  p_occurrence_id uuid,
  p_amount_minor bigint,
  p_paid_at timestamptz,
  p_payer_user_id uuid,
  p_payment_source_id uuid,
  p_client_mutation_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  occurrence record;
  obligation record;
  household_currency text;
  new_expense_id uuid;
begin
  select * into occurrence from public.obligation_occurrences where id = p_occurrence_id for update;
  if not public.can_operate_household(occurrence.household_id) then raise exception 'Operator access required'; end if;
  if occurrence.status <> 'scheduled' then raise exception 'Occurrence is not payable'; end if;
  select * into obligation from public.obligations where id = occurrence.obligation_id;
  select currency_code into household_currency from public.households where id = occurrence.household_id;
  insert into public.expenses (
    household_id, client_mutation_id, kind, status, summary, total_minor,
    currency_code, incurred_at, payer_user_id, category_id, payment_source_id, submitted_by
  ) values (
    occurrence.household_id, p_client_mutation_id, 'obligation_payment', 'approved',
    occurrence.title_snapshot, p_amount_minor, household_currency, p_paid_at,
    p_payer_user_id, obligation.category_id, p_payment_source_id, auth.uid()
  ) returning id into new_expense_id;
  insert into public.expense_items (expense_id, name, amount_minor, category_id)
  values (new_expense_id, occurrence.title_snapshot, p_amount_minor, obligation.category_id);
  update public.obligation_occurrences set status = 'completed', expense_id = new_expense_id,
    updated_at = now() where id = p_occurrence_id;
  return new_expense_id;
end;
$$;

create or replace function public.spending_analytics(
  p_household_id uuid,
  p_from timestamptz,
  p_until timestamptz
) returns table (
  period_day date,
  category_id uuid,
  category_name text,
  payer_user_id uuid,
  total_minor bigint
) language sql stable security definer set search_path = '' as $$
  select
    (e.incurred_at at time zone h.time_zone)::date,
    e.category_id,
    coalesce(c.name, 'Uncategorized'),
    e.payer_user_id,
    sum(e.total_minor)::bigint
  from public.expenses e
  join public.households h on h.id = e.household_id
  left join public.categories c on c.id = e.category_id
  where e.household_id = p_household_id
    and public.can_operate_household(p_household_id)
    and e.status = 'approved'
    and e.incurred_at >= p_from and e.incurred_at < p_until
  group by 1, 2, 3, 4
  order by 1;
$$;

grant execute on function public.create_chore(uuid, text, text, uuid, public.recurrence_frequency, timestamptz) to authenticated;
grant execute on function public.create_obligation(uuid, text, bigint, uuid, public.recurrence_frequency, date, time) to authenticated;
grant execute on function public.set_monthly_budget(uuid, uuid, date, bigint) to authenticated;
grant execute on function public.mark_obligation_paid(uuid, bigint, timestamptz, uuid, uuid, uuid) to authenticated;
grant execute on function public.spending_analytics(uuid, timestamptz, timestamptz) to authenticated;

select cron.schedule(
  'generate-home-occurrences',
  '23 2 * * *',
  $$select public.generate_scheduled_occurrences();$$
);
