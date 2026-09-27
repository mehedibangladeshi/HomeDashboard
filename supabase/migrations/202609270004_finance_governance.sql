drop policy households_update_operator on public.households;
create policy households_update_owner on public.households for update
using (public.is_household_owner(id)) with check (public.is_household_owner(id));

create or replace function public.protect_last_owner()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner') and
    (select count(*) from public.memberships where household_id = old.household_id and role = 'owner') <= 1 then
    raise exception 'A household must retain at least one Owner';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger memberships_retain_owner
before update or delete on public.memberships
for each row execute function public.protect_last_owner();

create or replace function public.correct_expense(
  p_expense_id uuid,
  p_expected_version integer,
  p_summary text,
  p_total_minor bigint,
  p_incurred_at timestamptz,
  p_category_id uuid,
  p_payment_source_id uuid,
  p_reason text
) returns integer language plpgsql security definer set search_path = '' as $$
declare old_row public.expenses; new_row public.expenses;
begin
  select * into old_row from public.expenses where id = p_expense_id for update;
  if not public.can_operate_household(old_row.household_id) then raise exception 'Operator access required'; end if;
  if old_row.status <> 'approved' then raise exception 'Only approved expenses can be corrected'; end if;
  if old_row.version <> p_expected_version then raise exception 'Expense changed; reload before correcting'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Correction reason is required'; end if;
  update public.expenses set
    summary = trim(p_summary), total_minor = p_total_minor, incurred_at = p_incurred_at,
    category_id = p_category_id, payment_source_id = p_payment_source_id,
    correction_reason = p_reason, version = version + 1, updated_at = now()
  where id = p_expense_id returning * into new_row;
  insert into public.audit_events (
    household_id, actor_user_id, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    old_row.household_id, auth.uid(), 'corrected', 'expense', p_expense_id,
    to_jsonb(old_row), to_jsonb(new_row), p_reason
  );
  return new_row.version;
end;
$$;

create or replace function public.void_expense(p_expense_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare old_row public.expenses; new_row public.expenses;
begin
  select * into old_row from public.expenses where id = p_expense_id for update;
  if not public.can_operate_household(old_row.household_id) then raise exception 'Operator access required'; end if;
  if old_row.status <> 'approved' then raise exception 'Only approved expenses can be voided'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Void reason is required'; end if;
  update public.expenses set status = 'voided', correction_reason = p_reason,
    version = version + 1, updated_at = now() where id = p_expense_id returning * into new_row;
  insert into public.audit_events (
    household_id, actor_user_id, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    old_row.household_id, auth.uid(), 'voided', 'expense', p_expense_id,
    to_jsonb(old_row), to_jsonb(new_row), p_reason
  );
end;
$$;

create or replace function public.materialize_budget_alerts()
returns integer language plpgsql security definer set search_path = '' as $$
declare inserted_count integer;
begin
  with spending as (
    select e.household_id, coalesce(i.category_id, e.category_id) category_id,
      date_trunc('month', e.incurred_at at time zone h.time_zone)::date month_start,
      sum(case when i.id is null then e.total_minor else i.amount_minor end)::bigint spent_minor
    from public.expenses e
    join public.households h on h.id = e.household_id
    left join public.expense_items i on i.expense_id = e.id
    where e.status = 'approved'
    group by 1, 2, 3
  ), thresholds as (
    select b.household_id, b.category_id, b.month_start, b.amount_minor,
      s.spent_minor, c.name,
      case when s.spent_minor >= b.amount_minor then 100
           when s.spent_minor * 100 >= b.amount_minor * 80 then 80 end threshold
    from public.budgets b
    join spending s using (household_id, category_id, month_start)
    join public.categories c on c.id = b.category_id
  )
  insert into public.notifications (household_id, user_id, dedupe_key, title, body, scheduled_for)
  select t.household_id, m.user_id,
    'budget:' || t.category_id || ':' || t.month_start || ':' || t.threshold,
    case t.threshold when 100 then 'Budget reached' else 'Budget heads-up' end,
    t.name || ' is at ' || t.threshold || '% of its monthly budget.', now()
  from thresholds t
  join public.memberships m on m.household_id = t.household_id and m.role in ('owner', 'manager')
  where t.threshold is not null
  on conflict (user_id, dedupe_key) do nothing;
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

grant execute on function public.correct_expense(uuid, integer, text, bigint, timestamptz, uuid, uuid, text) to authenticated;
grant execute on function public.void_expense(uuid, text) to authenticated;

select cron.schedule(
  'materialize-budget-alerts',
  '*/15 * * * *',
  $$select public.materialize_budget_alerts();$$
);
