-- Invitations are accepted only after authentication, not from signup metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(user_id,display_name,avatar_url)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1),''),
    new.raw_user_meta_data->>'avatar_url');
  return new;
end;
$$;

create or replace function public.accept_household_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invitation public.invitations; identity auth.users; membership public.memberships;
begin
  select * into identity from auth.users where id = auth.uid() and email_confirmed_at is not null;
  if not found then raise exception 'Verified email required'; end if;
  select * into invitation from public.invitations
    where token_hash = encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if not found or invitation.expires_at <= now() or lower(invitation.email::text) <> lower(identity.email) then
    raise exception 'Invitation is invalid, expired or belongs to another email';
  end if;
  perform 1 from public.households where id = invitation.household_id and deleted_at is null for update;
  if not found then raise exception 'Household is unavailable'; end if;
  select * into membership from public.memberships where user_id = auth.uid();
  if found then
    if membership.household_id <> invitation.household_id then raise exception 'Already belongs to another household'; end if;
    -- Existing members never receive an unexpected privilege change from a link.
    update public.invitations set accepted_at = coalesce(accepted_at,now()) where id = invitation.id;
    return invitation.household_id;
  end if;
  if invitation.accepted_at is not null then raise exception 'Invitation was already used'; end if;
  insert into public.memberships(household_id,user_id,role)
    values(invitation.household_id,auth.uid(),invitation.role);
  update public.invitations set accepted_at = now() where id = invitation.id;
  insert into public.audit_events(household_id,actor_user_id,action,entity_type,entity_id)
    values(invitation.household_id,auth.uid(),'invitation_accepted','invitation',invitation.id);
  return invitation.household_id;
end;
$$;
grant execute on function public.accept_household_invitation(text) to authenticated,service_role;

create or replace function public.correct_expense(
  p_expense_id uuid,p_expected_version integer,p_summary text,p_total_minor bigint,
  p_incurred_at timestamptz,p_category_id uuid,p_payment_source_id uuid,p_reason text
) returns integer language plpgsql security definer set search_path = '' as $$
declare old_row public.expenses; new_row public.expenses; old_items jsonb;
begin
  select * into old_row from public.expenses where id=p_expense_id for update;
  if not public.can_operate_household(old_row.household_id) then raise exception 'Operator access required'; end if;
  if old_row.status <> 'approved' then raise exception 'Only approved expenses can be corrected'; end if;
  if old_row.version <> p_expected_version then raise exception 'Expense changed; reload before correcting'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Correction reason is required'; end if;
  select jsonb_agg(to_jsonb(i)) into old_items from public.expense_items i where expense_id=p_expense_id;
  update public.expenses set summary=trim(p_summary),total_minor=p_total_minor,
    incurred_at=p_incurred_at,category_id=p_category_id,payment_source_id=p_payment_source_id,
    correction_reason=p_reason,version=version+1,updated_at=now()
  where id=p_expense_id returning * into new_row;
  delete from public.expense_items where expense_id=p_expense_id;
  insert into public.expense_items(expense_id,name,amount_minor,category_id)
    values(p_expense_id,trim(p_summary),p_total_minor,p_category_id);
  insert into public.audit_events(household_id,actor_user_id,action,entity_type,entity_id,before_data,after_data,reason)
    values(old_row.household_id,auth.uid(),'corrected','expense',p_expense_id,
      to_jsonb(old_row)||jsonb_build_object('items',old_items),to_jsonb(new_row),p_reason);
  return new_row.version;
end;
$$;

drop policy chores_update on public.chores;
drop policy chores_delete on public.chores;
create policy chores_update on public.chores for update using (
  public.is_household_member(household_id) and
  (public.can_operate_household(household_id) or (assignee_user_id=auth.uid() and created_by=auth.uid()))
) with check (
  public.is_household_member(household_id) and
  (public.can_operate_household(household_id) or (assignee_user_id=auth.uid() and created_by=auth.uid()))
);
create policy chores_delete on public.chores for delete using (
  public.is_household_member(household_id) and
  (public.can_operate_household(household_id) or (assignee_user_id=auth.uid() and created_by=auth.uid()))
);
