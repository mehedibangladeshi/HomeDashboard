create or replace function public.attach_expense_receipt(
  p_expense_id uuid,
  p_receipt_path text
) returns void language plpgsql security definer set search_path = '' as $$
declare target public.expenses;
begin
  select * into target from public.expenses where id = p_expense_id for update;
  if not public.can_operate_household(target.household_id) and
    not (target.submitted_by = auth.uid() and target.status = 'pending') then
    raise exception 'Not permitted';
  end if;
  if split_part(p_receipt_path, '/', 1) <> target.household_id::text then
    raise exception 'Receipt path does not belong to this household';
  end if;
  update public.expenses set receipt_path = p_receipt_path,
    version = version + 1, updated_at = now() where id = p_expense_id;
end;
$$;

grant execute on function public.attach_expense_receipt(uuid, text) to authenticated;
