create or replace function public.mark_obligation_paid(
  p_occurrence_id uuid,p_amount_minor bigint,p_paid_at timestamptz,
  p_payer_user_id uuid,p_payment_source_id uuid,p_client_mutation_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare occurrence public.obligation_occurrences; obligation public.obligations;
  household_currency text; new_expense_id uuid;
begin
  select * into occurrence from public.obligation_occurrences where id=p_occurrence_id for update;
  if not public.can_operate_household(occurrence.household_id) then raise exception 'Operator access required'; end if;
  if occurrence.status='completed' and occurrence.expense_id is not null then return occurrence.expense_id; end if;
  if occurrence.status<>'scheduled' then raise exception 'Occurrence is not payable'; end if;
  select * into obligation from public.obligations where id=occurrence.obligation_id;
  select currency_code into household_currency from public.households where id=occurrence.household_id;
  insert into public.expenses(household_id,client_mutation_id,kind,status,summary,total_minor,
    currency_code,incurred_at,payer_user_id,category_id,payment_source_id,submitted_by)
  values(occurrence.household_id,p_client_mutation_id,'obligation_payment','approved',
    occurrence.title_snapshot,p_amount_minor,household_currency,p_paid_at,p_payer_user_id,
    obligation.category_id,p_payment_source_id,auth.uid()) returning id into new_expense_id;
  insert into public.expense_items(expense_id,name,amount_minor,category_id)
    values(new_expense_id,occurrence.title_snapshot,p_amount_minor,obligation.category_id);
  update public.obligation_occurrences set status='completed',expense_id=new_expense_id,updated_at=now() where id=p_occurrence_id;
  insert into public.audit_events(household_id,actor_user_id,action,entity_type,entity_id,after_data)
    select occurrence.household_id,auth.uid(),'payment_recorded','expense',new_expense_id,to_jsonb(e)
    from public.expenses e where id=new_expense_id;
  return new_expense_id;
end;
$$;
