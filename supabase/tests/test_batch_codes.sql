-- Behavioural tests for s171 (a code per batch with its history). Run after s171 on a database with batches.
\set ON_ERROR_STOP on
\set QUIET on
create temp table c_results (name text, ok boolean, detail text);
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into c_results values (n, coalesce(cond, false), d);
$$;
insert into store.suppliers (name) values ('s171 مورد أ'), ('s171 مورد ب');
select pg_temp.check('new supplier gets S<id>', (select bool_and(letter = 'S' || id) from store.suppliers where name like 's171 %'));
select id as sa from store.suppliers where name = 's171 مورد أ' \gset
select id as sb from store.suppliers where name = 's171 مورد ب' \gset
select id as pid from store.products order by id limit 1 \gset
insert into store.code_batches (product_id, supplier_id, cost, added, duplicates, created_by)
values (:pid, :sa, 100, 0, 0, '60e166af-1366-47cc-81f9-791a4585c66e') returning id as b1 \gset
select pg_temp.check('a new batch: its supplier letter and number', (select code = 'S' || :sa || '1' from store.code_batches where id = :b1));
update store.code_batches set supplier_id = :sb where id = :b1;
select pg_temp.check('a change of supplier adds a part', (select code = 'S' || :sa || '1-S' || :sb || '1' from store.code_batches where id = :b1));
update store.code_batches set supplier_id = :sa where id = :b1;
select pg_temp.check('back to an earlier supplier adds one too', (select code = 'S' || :sa || '1-S' || :sb || '1-S' || :sa || '2' from store.code_batches where id = :b1));
select pg_temp.check('codes are unique', (select count(*) = count(distinct code) from store.code_batches));
select name, ok, detail from c_results order by ok, name;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from c_results;
