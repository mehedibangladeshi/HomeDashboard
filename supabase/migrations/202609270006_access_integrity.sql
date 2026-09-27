-- Forward-only security fixes: active membership, tenant references and RPC grants.
create or replace function public.household_role_for(p_household_id uuid)
returns public.household_role language sql stable security definer set search_path = '' as $$
  select m.role from public.memberships m join public.households h on h.id = m.household_id
  where m.household_id = p_household_id and m.user_id = auth.uid() and h.deleted_at is null;
$$;

create or replace function public.is_household_member(p_household_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.household_role_for(p_household_id) is not null;
$$;

-- Restore authorization must work after normal membership access is suspended.
create or replace function public.restore_household(p_household_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.memberships where household_id = p_household_id
      and user_id = auth.uid() and role = 'owner') then
    raise exception 'Owner access required';
  end if;
  update public.households set deleted_at = null, purge_after = null, updated_at = now()
  where id = p_household_id and purge_after > now();
  if not found then raise exception 'Recovery window expired or household is not deleted'; end if;
end;
$$;

create or replace function public.recoverable_households()
returns table(id uuid, name text, purge_after timestamptz)
language sql stable security definer set search_path = '' as $$
  select h.id, h.name, h.purge_after from public.households h
  join public.memberships m on m.household_id = h.id
  where m.user_id = auth.uid() and m.role = 'owner' and h.deleted_at is not null
    and h.purge_after > now();
$$;

create or replace function public.protect_last_owner()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Parent deletion may cascade memberships: it must not block legitimate purge.
  perform 1 from public.households where id = old.household_id for update;
  if not found then return old; end if;
  if tg_op = 'UPDATE' and (new.household_id <> old.household_id or new.user_id <> old.user_id) then
    raise exception 'Membership identity cannot be changed';
  end if;
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner') and
    (select count(*) from public.memberships where household_id = old.household_id and role = 'owner') <= 1 then
    raise exception 'A household must retain at least one Owner';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.check_household_references()
returns trigger language plpgsql security definer set search_path = '' as $$
declare payload jsonb := to_jsonb(new); target_household uuid;
begin
  if tg_op = 'UPDATE' and payload ->> 'household_id' is distinct from to_jsonb(old) ->> 'household_id' then
    raise exception 'Household identity cannot be changed';
  end if;
  target_household := (payload ->> 'household_id')::uuid;
  if tg_table_name = 'expense_items' then
    if tg_op = 'UPDATE' and new.expense_id <> old.expense_id then raise exception 'Expense identity cannot be changed'; end if;
    select household_id into target_household from public.expenses where id = new.expense_id;
  end if;
  if payload ->> 'category_id' is not null and not exists (
    select 1 from public.categories where id = (payload ->> 'category_id')::uuid and household_id = target_household
  ) then raise exception 'Category must belong to this household'; end if;
  if payload ->> 'payment_source_id' is not null and not exists (
    select 1 from public.payment_sources where id = (payload ->> 'payment_source_id')::uuid and household_id = target_household
  ) then raise exception 'Payment source must belong to this household'; end if;
  if payload ->> 'payer_user_id' is not null and not exists (
    select 1 from public.memberships where user_id = (payload ->> 'payer_user_id')::uuid and household_id = target_household
  ) then raise exception 'Payer must belong to this household'; end if;
  if payload ->> 'assignee_user_id' is not null and not exists (
    select 1 from public.memberships where user_id = (payload ->> 'assignee_user_id')::uuid and household_id = target_household
  ) then raise exception 'Assignee must belong to this household'; end if;
  if payload ->> 'chore_id' is not null and not exists (
    select 1 from public.chores where id = (payload ->> 'chore_id')::uuid and household_id = target_household
  ) then raise exception 'Chore must belong to this household'; end if;
  if payload ->> 'obligation_id' is not null and not exists (
    select 1 from public.obligations where id = (payload ->> 'obligation_id')::uuid and household_id = target_household
  ) then raise exception 'Obligation must belong to this household'; end if;
  if payload ->> 'expense_id' is not null and tg_table_name <> 'expense_items' and not exists (
    select 1 from public.expenses where id = (payload ->> 'expense_id')::uuid and household_id = target_household
  ) then raise exception 'Expense must belong to this household'; end if;
  if payload ->> 'parent_id' is not null and not exists (
    select 1 from public.categories where id = (payload ->> 'parent_id')::uuid and household_id = target_household
  ) then raise exception 'Parent category must belong to this household'; end if;
  if tg_table_name in ('expenses', 'budgets') and payload ->> 'currency_code' is distinct from
      (select currency_code from public.households where id = target_household) then
    raise exception 'Currency mismatch';
  end if;
  return new;
end;
$$;

do $$ declare target text;
begin
  foreach target in array array['expenses','expense_items','budgets','obligations','obligation_occurrences','chores','chore_occurrences','categories'] loop
    execute format('create trigger tenant_references before insert or update on public.%I for each row execute function public.check_household_references()', target);
  end loop;
end $$;

alter table public.expense_items add constraint expense_item_amount_positive check (amount_minor > 0);

drop policy expenses_finance_or_own_submission_read on public.expenses;
create policy expenses_finance_or_own_submission_read on public.expenses for select using (
  public.is_household_member(household_id) and
  (public.can_operate_household(household_id) or submitted_by = auth.uid())
);
drop policy expense_items_finance_or_own_read on public.expense_items;
create policy expense_items_finance_or_own_read on public.expense_items for select using (
  exists (select 1 from public.expenses e where e.id = expense_id and
    public.is_household_member(e.household_id) and
    (public.can_operate_household(e.household_id) or e.submitted_by = auth.uid()))
);

-- Ordinary API clients cannot fetch even encrypted Google credential material.
drop policy calendar_connections_owner_all on public.calendar_connections;

create or replace function public.can_access_receipt(p_path text, p_write boolean default false)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.expenses e
    where p_path = e.household_id::text || '/' || e.id::text || '.jpg'
      and public.is_household_member(e.household_id)
      and (public.can_operate_household(e.household_id) or
        (e.submitted_by = auth.uid() and (not p_write or e.status = 'pending'))));
$$;

drop policy receipt_operator_read on storage.objects;
drop policy receipt_uploader_insert on storage.objects;
drop policy receipt_operator_update on storage.objects;
drop policy receipt_operator_delete on storage.objects;
create policy receipt_read on storage.objects for select using (bucket_id = 'receipts' and public.can_access_receipt(name));
create policy receipt_insert on storage.objects for insert with check (bucket_id = 'receipts' and public.can_access_receipt(name, true));
create policy receipt_update on storage.objects for update using (bucket_id = 'receipts' and public.can_access_receipt(name, true))
  with check (bucket_id = 'receipts' and public.can_access_receipt(name, true));
create policy receipt_delete on storage.objects for delete using (bucket_id = 'receipts' and public.can_access_receipt(name, true));

create or replace function public.attach_expense_receipt(p_expense_id uuid, p_receipt_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare target public.expenses;
begin
  select * into target from public.expenses where id = p_expense_id for update;
  if not found or not public.can_access_receipt(p_receipt_path, true) or
      p_receipt_path <> target.household_id::text || '/' || target.id::text || '.jpg' then
    raise exception 'Not permitted';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'receipts' and name = p_receipt_path) then
    raise exception 'Upload the receipt before attaching it';
  end if;
  update public.expenses set receipt_path = p_receipt_path, version = version + 1, updated_at = now()
    where id = p_expense_id and receipt_path is distinct from p_receipt_path;
end;
$$;

-- PostgreSQL grants EXECUTE to PUBLIC by default; explicitly allow only APIs.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
grant execute on function public.household_role_for(uuid), public.is_household_member(uuid),
  public.can_operate_household(uuid), public.is_household_owner(uuid),
  public.can_access_receipt(text, boolean) to authenticated;
grant execute on function public.create_household(text,text,text),
  public.create_purchase(uuid,uuid,text,bigint,text,timestamptz,uuid,uuid,uuid,text,jsonb),
  public.review_expense(uuid,public.expense_status,text), public.complete_chore(uuid),
  public.create_chore(uuid,text,text,uuid,public.recurrence_frequency,timestamptz),
  public.create_obligation(uuid,text,bigint,uuid,public.recurrence_frequency,date,time),
  public.set_monthly_budget(uuid,uuid,date,bigint),
  public.mark_obligation_paid(uuid,bigint,timestamptz,uuid,uuid,uuid),
  public.spending_analytics(uuid,timestamptz,timestamptz),
  public.correct_expense(uuid,integer,text,bigint,timestamptz,uuid,uuid,text),
  public.void_expense(uuid,text), public.attach_expense_receipt(uuid,text),
  public.mark_household_for_deletion(uuid), public.restore_household(uuid),
  public.recoverable_households() to authenticated;

alter default privileges in schema public revoke execute on functions from public;
