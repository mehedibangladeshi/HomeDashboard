begin;
select no_plan();
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 ('10000000-1111-4111-8111-111111111111','workflow-owner@home.test',now(),'{}'),
 ('20000000-2222-4222-8222-222222222222','workflow-member@home.test',now(),'{}');
select set_config('request.jwt.claim.sub','10000000-1111-4111-8111-111111111111',true);
select set_config('test.household', public.create_household('Workflow Home','BDT','Asia/Dhaka')::text,true);
select set_config('test.category',(select id::text from public.categories where household_id=current_setting('test.household')::uuid and name='Rent'),true);

select set_config('test.obligation',public.create_obligation(current_setting('test.household')::uuid,'Rent',1500000,current_setting('test.category')::uuid,'monthly','2020-01-31','09:00')::text,true);
select ok(exists(select 1 from public.obligation_occurrences where obligation_id=current_setting('test.obligation')::uuid and due_at>now()),'Old monthly obligations continue generating future occurrences');
select set_config('test.chore',public.create_chore(current_setting('test.household')::uuid,'Daily cleaning',null,'10000000-1111-4111-8111-111111111111','daily','2020-01-01 09:00+06')::text,true);
select ok(exists(select 1 from public.chore_occurrences where chore_id=current_setting('test.chore')::uuid and due_at>now()),'Old daily chores continue generating future occurrences');
select set_config('test.occurrence',(select id::text from public.obligation_occurrences where obligation_id=current_setting('test.obligation')::uuid and due_at>now() order by due_at limit 1),true);
select set_config('test.expense',public.mark_obligation_paid(current_setting('test.occurrence')::uuid,1500000,now(),'10000000-1111-4111-8111-111111111111',null,'30000000-3333-4333-8333-333333333333')::text,true);
select is(public.mark_obligation_paid(current_setting('test.occurrence')::uuid,1500000,now(),'10000000-1111-4111-8111-111111111111',null,'40000000-4444-4444-8444-444444444444')::text,current_setting('test.expense'),'Payment retry returns the original expense');
select is((select count(*) from public.expenses where household_id=current_setting('test.household')::uuid),1::bigint,'Repeated payment does not duplicate spending');
select lives_ok(format('select public.correct_expense(%L,1,''Rent corrected'',1600000,now(),%L,null,''Actual rent revised'')',current_setting('test.expense'),current_setting('test.category')),'Expense correction is accepted with a reason');
select is((select sum(amount_minor) from public.expense_items where expense_id=current_setting('test.expense')::uuid),1600000::numeric,'Corrected line items reconcile with expense total');
select is((public.household_dashboard(current_setting('test.household')::uuid)->>'spent_month_minor')::bigint,1600000::bigint,'Dashboard uses authoritative monthly expense totals');
select ok(exists(select 1 from public.audit_events where entity_id=current_setting('test.expense')::uuid and action='corrected' and before_data?'items'),'Correction retains original item breakdown in audit history');

insert into public.invitations(household_id,email,role,token_hash,invited_by,expires_at)
values(current_setting('test.household')::uuid,'workflow-member@home.test','member',encode(extensions.digest('workflow-secret','sha256'),'hex'),'10000000-1111-4111-8111-111111111111',now()+interval '1 day');
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-2222-4222-8222-222222222222',true);
select lives_ok($$select public.accept_household_invitation('workflow-secret')$$,'Existing verified account accepts invitation');
select lives_ok($$select public.accept_household_invitation('workflow-secret')$$,'Repeated acceptance is idempotent');
select is((select count(*) from public.memberships where user_id=auth.uid()),1::bigint,'Invitation creates exactly one membership');
select ok(not public.household_dashboard(current_setting('test.household')::uuid)?'spent_month_minor','Member dashboard never returns financial totals');
select throws_ok($$select public.accept_household_invitation('wrong-secret')$$,'P0001','Invitation is invalid, expired or belongs to another email','Invalid invitation rejected');
select throws_ok(format('select public.cancel_chore(%L)',current_setting('test.chore')),'P0001','Not permitted','Member cannot cancel an Owner chore');
select throws_ok(format('select public.edit_chore(%L,''Hijacked'',auth.uid(),''daily'',now())',current_setting('test.chore')),'P0001','Not permitted','Member cannot reassign an Owner chore');
select set_config('request.jwt.claim.sub','10000000-1111-4111-8111-111111111111',true);
select lives_ok(format('select public.edit_chore(%L,''Updated cleaning'',auth.uid(),''weekly'',now()+interval ''1 day'')',current_setting('test.chore')),'Owner edits chore and regenerates future schedule');
select ok(exists(select 1 from public.chore_occurrences where chore_id=current_setting('test.chore')::uuid and title_snapshot='Updated cleaning' and status='scheduled'),'Updated title appears on future occurrences');
select lives_ok(format('select public.cancel_chore(%L)',current_setting('test.chore')),'Owner cancels recurring chore');
select is((select count(*) from public.chore_occurrences where chore_id=current_setting('test.chore')::uuid and status='scheduled'),0::bigint,'Cancellation leaves no scheduled occurrences');
reset role;
select * from finish();
rollback;
