create or replace function public.household_dashboard(p_household_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare local_today date; local_zone text; result jsonb;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Not permitted'; end if;
  select time_zone into local_zone from public.households where id = p_household_id;
  local_today := (now() at time zone local_zone)::date;
  result := jsonb_build_object(
    'chores_due', (select count(*) from public.chore_occurrences where household_id = p_household_id
      and status = 'scheduled' and (due_at at time zone local_zone)::date = local_today),
    'chores_overdue', (select count(*) from public.chore_occurrences where household_id = p_household_id
      and status = 'scheduled' and due_at < now()),
    'events_today', (select count(*) from public.household_events where household_id = p_household_id
      and status = 'scheduled' and (starts_at at time zone local_zone)::date = local_today)
  );
  if public.can_operate_household(p_household_id) then
    result := result || jsonb_build_object(
      'spent_month_minor', (select coalesce(sum(total_minor), 0) from public.expenses
        where household_id = p_household_id and status = 'approved'
          and incurred_at >= date_trunc('month', local_today::timestamp) at time zone local_zone
          and incurred_at < (date_trunc('month', local_today::timestamp) + interval '1 month') at time zone local_zone),
      'pending_submissions', (select count(*) from public.expenses where household_id = p_household_id and status = 'pending'),
      'payments_due', (select count(*) from public.obligation_occurrences where household_id = p_household_id
        and status = 'scheduled' and due_at <= now() + interval '7 days')
    );
  end if;
  return result;
end;
$$;
grant execute on function public.household_dashboard(uuid) to authenticated, service_role;
