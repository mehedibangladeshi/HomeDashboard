begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data) values
 ('11111111-1111-4111-8111-111111111111', 'rls-owner@home.test', '{}'),
 ('22222222-2222-4222-8222-222222222222', 'rls-manager@home.test', '{}'),
 ('33333333-3333-4333-8333-333333333333', 'rls-member@home.test', '{}'),
 ('44444444-4444-4444-8444-444444444444', 'rls-other@home.test', '{}');
insert into public.households (id, name, currency_code, created_by) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Policy Test', 'BDT', '11111111-1111-4111-8111-111111111111'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Other Policy Test', 'BDT', '44444444-4444-4444-8444-444444444444');
insert into public.memberships (household_id,user_id,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','owner'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','manager'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','33333333-3333-4333-8333-333333333333','member'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444','owner');
insert into public.categories (id,household_id,name) values
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Test Grocery'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Other Grocery');
insert into public.expenses (id,household_id,client_mutation_id,status,summary,total_minor,currency_code,incurred_at,payer_user_id,submitted_by) values
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',gen_random_uuid(),'approved','Owner groceries',10000,'BDT',now(),'11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111'),
 ('ffffffff-ffff-4fff-8fff-ffffffffffff','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',gen_random_uuid(),'pending','Member groceries',20000,'BDT',now(),'33333333-3333-4333-8333-333333333333','33333333-3333-4333-8333-333333333333');

select ok(not has_function_privilege('anon', 'public.create_purchase(uuid,uuid,text,bigint,text,timestamptz,uuid,uuid,uuid,text,jsonb)', 'EXECUTE'), 'Anonymous cannot invoke purchase RPC');
select ok(not has_function_privilege('authenticated', 'public.purge_expired_households()', 'EXECUTE'), 'Clients cannot purge households');
select ok(not has_function_privilege('authenticated', 'public.materialize_due_notifications(timestamptz)', 'EXECUTE'), 'Clients cannot run notification worker');
select ok(not has_function_privilege('authenticated', 'public.generate_scheduled_occurrences(uuid)', 'EXECUTE'), 'Clients cannot run occurrence worker');

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
select is((select count(*) from public.expenses where household_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),1::bigint,'Member sees only own submission');
select is((select count(*) from public.households where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),0::bigint,'Member cannot read another household');
select throws_ok($$select public.set_monthly_budget('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc',date_trunc('month',now())::date,10000)$$,'P0001','Operator access required','Member cannot set budgets');
select throws_ok($$select public.review_expense('ffffffff-ffff-4fff-8fff-ffffffffffff','approved',null)$$,'P0001','Not permitted','Member cannot approve spending');
select ok(public.can_access_receipt('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/ffffffff-ffff-4fff-8fff-ffffffffffff.jpg',true),'Member can upload own pending receipt');
select ok(not public.can_access_receipt('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee.jpg',true),'Member cannot replace another receipt');
select ok(not public.can_access_receipt('bad/path.jpg',true),'Malformed receipt path denied');

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select is((select count(*) from public.expenses where household_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),2::bigint,'Manager sees household ledger');
select throws_ok($$select public.mark_household_for_deletion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,'P0001','Owner access required','Manager cannot delete household');
update public.memberships set role='owner' where user_id='33333333-3333-4333-8333-333333333333';
select is((select role::text from public.memberships where user_id='33333333-3333-4333-8333-333333333333'),'member','Manager cannot promote Member');
select throws_ok($$select public.set_monthly_budget('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','dddddddd-dddd-4ddd-8ddd-dddddddddddd',date_trunc('month',now())::date,10000)$$,'P0001','Category must belong to this household','Cross-household budget category denied');

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select throws_ok($$update public.memberships set role='member' where user_id='11111111-1111-4111-8111-111111111111'$$,'P0001','A household must retain at least one Owner','Last Owner cannot be demoted');
select throws_ok($$select public.create_purchase(gen_random_uuid(),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Foreign payer',100,'BDT',now(),'44444444-4444-4444-8444-444444444444',null,null,null,'[{"name":"item","amount_minor":100}]')$$,'P0001','Payer must belong to this household','Foreign payer denied');
select lives_ok($$select public.mark_household_for_deletion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,'Owner schedules deletion');
select is((select count(*) from public.expenses where household_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),0::bigint,'Deleted household ledger is inaccessible');
select is((select count(*) from public.recoverable_households()),1::bigint,'Owner sees recovery option');
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select throws_ok($$select public.restore_household('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,'P0001','Owner access required','Manager cannot restore household');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select lives_ok($$select public.restore_household('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,'Owner restores during recovery window');
select is((select count(*) from public.expenses where household_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),2::bigint,'Restored ledger is accessible');

reset role;
select * from finish();
rollback;
