-- Give PostgREST an explicit public relationship for member display names.
alter table public.memberships add constraint memberships_profile_fk
  foreign key(user_id) references public.profiles(user_id) on delete cascade;

create or replace function public.edit_chore(p_chore_id uuid,p_title text,
  p_assignee_user_id uuid,p_frequency public.recurrence_frequency,p_starts_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare task public.chores;
begin
  select * into task from public.chores where id=p_chore_id for update;
  if not public.is_household_member(task.household_id) or not (
    public.can_operate_household(task.household_id) or
    (task.created_by=auth.uid() and task.assignee_user_id=auth.uid() and p_assignee_user_id=auth.uid())
  ) then raise exception 'Not permitted'; end if;
  update public.chores set title=trim(p_title),assignee_user_id=p_assignee_user_id,
    frequency=p_frequency,starts_at=p_starts_at,updated_at=now() where id=p_chore_id;
  delete from public.chore_occurrences where chore_id=p_chore_id and status='scheduled' and due_at>=now();
  perform public.generate_scheduled_occurrences(task.household_id);
end;
$$;

create or replace function public.cancel_chore(p_chore_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare task public.chores;
begin
  select * into task from public.chores where id=p_chore_id for update;
  if not public.is_household_member(task.household_id) or not (
    public.can_operate_household(task.household_id) or
    (task.created_by=auth.uid() and task.assignee_user_id=auth.uid())
  ) then raise exception 'Not permitted'; end if;
  update public.chores set active=false,updated_at=now() where id=p_chore_id;
  update public.chore_occurrences set status='cancelled',updated_at=now() where chore_id=p_chore_id and status='scheduled';
end;
$$;
grant execute on function public.edit_chore(uuid,text,uuid,public.recurrence_frequency,timestamptz),
  public.cancel_chore(uuid) to authenticated,service_role;
