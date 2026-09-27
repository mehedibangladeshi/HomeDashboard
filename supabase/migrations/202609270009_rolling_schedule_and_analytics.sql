create or replace function public.generate_scheduled_occurrences(p_household_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare task record; bill record; candidate timestamptz; local_start timestamp;
  local_date date; base_index integer; inserted_count integer := 0; batch_count integer;
begin
  for task in select c.*,h.time_zone from public.chores c join public.households h on h.id=c.household_id
    where c.active and h.deleted_at is null and (p_household_id is null or c.household_id=p_household_id)
  loop
    local_start := task.starts_at at time zone task.time_zone;
    base_index := case task.frequency
      when 'once' then 0
      when 'monthly' then greatest(0,(extract(year from age(now() at time zone task.time_zone,local_start))*12+
        extract(month from age(now() at time zone task.time_zone,local_start)))::integer-1)
      when 'weekly' then greatest(0,((now() at time zone task.time_zone)::date-local_start::date)/7-1)
      else greatest(0,((now() at time zone task.time_zone)::date-local_start::date)-1) end;
    for counter in base_index..base_index+61 loop
      candidate := (case task.frequency
        when 'once' then local_start
        when 'weekly' then local_start+make_interval(weeks=>counter)
        when 'monthly' then local_start+make_interval(months=>counter)
        else local_start+make_interval(days=>counter) end) at time zone task.time_zone;
      if task.frequency='once' and counter>0 then exit; end if;
      if candidate>now()+interval '60 days' then exit; end if;
      if task.frequency='weekdays' and extract(isodow from candidate at time zone task.time_zone)>5 then continue; end if;
      insert into public.chore_occurrences(household_id,chore_id,title_snapshot,assignee_user_id,due_at)
      values(task.household_id,task.id,task.title,task.assignee_user_id,candidate)
      on conflict(chore_id,due_at) do nothing;
      get diagnostics batch_count=row_count;
      inserted_count:=inserted_count+batch_count;
    end loop;
  end loop;
  for bill in select o.*,h.time_zone from public.obligations o join public.households h on h.id=o.household_id
    where o.active and h.deleted_at is null and (p_household_id is null or o.household_id=p_household_id)
  loop
    base_index := case bill.frequency
      when 'once' then 0
      when 'monthly' then greatest(0,(extract(year from age((now() at time zone bill.time_zone)::date,bill.starts_on))*12+
        extract(month from age((now() at time zone bill.time_zone)::date,bill.starts_on)))::integer-1)
      when 'weekly' then greatest(0,((now() at time zone bill.time_zone)::date-bill.starts_on)/7-1)
      else greatest(0,((now() at time zone bill.time_zone)::date-bill.starts_on)-1) end;
    for counter in base_index..base_index+61 loop
      local_date := case bill.frequency
        when 'once' then bill.starts_on
        when 'weekly' then bill.starts_on+counter*7
        when 'monthly' then (bill.starts_on+make_interval(months=>counter))::date
        else bill.starts_on+counter end;
      if bill.frequency='once' and counter>0 then exit; end if;
      candidate := (local_date+bill.due_time) at time zone bill.time_zone;
      if candidate>now()+interval '60 days' then exit; end if;
      if bill.frequency='weekdays' and extract(isodow from local_date)>5 then continue; end if;
      insert into public.obligation_occurrences(household_id,obligation_id,title_snapshot,due_at)
      values(bill.household_id,bill.id,bill.title,candidate)
      on conflict(obligation_id,due_at) do nothing;
      get diagnostics batch_count=row_count;
      inserted_count:=inserted_count+batch_count;
    end loop;
  end loop;
  return inserted_count;
end;
$$;

create or replace function public.spending_analytics(p_household_id uuid,p_from timestamptz,p_until timestamptz)
returns table(period_day date,category_id uuid,category_name text,payer_user_id uuid,total_minor bigint)
language sql stable security definer set search_path = '' as $$
  select (e.incurred_at at time zone h.time_zone)::date,coalesce(i.category_id,e.category_id),
    coalesce(c.name,'Uncategorized'),e.payer_user_id,
    sum(case when i.id is null then e.total_minor else i.amount_minor end)::bigint
  from public.expenses e join public.households h on h.id=e.household_id
  left join public.expense_items i on i.expense_id=e.id
  left join public.categories c on c.id=coalesce(i.category_id,e.category_id)
  where e.household_id=p_household_id and public.can_operate_household(p_household_id)
    and e.status='approved' and e.incurred_at>=p_from and e.incurred_at<p_until
  group by 1,2,3,4 order by 1;
$$;

create or replace function public.spending_analytics_window(p_household_id uuid,p_from date,p_until date)
returns table(period_day date,category_id uuid,category_name text,payer_user_id uuid,total_minor bigint)
language sql stable security definer set search_path = '' as $$
  select a.* from public.households h cross join lateral
    public.spending_analytics(p_household_id,p_from::timestamp at time zone h.time_zone,p_until::timestamp at time zone h.time_zone) a
  where h.id=p_household_id;
$$;
grant execute on function public.spending_analytics_window(uuid,date,date) to authenticated,service_role;
