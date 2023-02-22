/* connect as migration user */
\connect - migrator
SET client_min_messages = WARNING;

/* set up staging schemas */
SELECT db_migrate_prepare(
   plugin => 'mysql_migrator',
   server => 'mysql',
   only_schemas => '{partitions}'
);

/* quote character expression */
UPDATE pgsql_stage.columns 
   SET default_value = quote_literal(default_value)
   WHERE NOT regexp_like(default_value, '^\-?[0-9]+$')
   AND default_value <> 'CURRENT_TIMESTAMP';

/* convert simple table to partitioned table */
INSERT INTO pgsql_stage.partitions 
   (schema, table_name, partition_name, orig_name, type, key, is_default, values)
VALUES
   ('partitions', 'employees', 'employees_2000', 'employees_2000', 'RANGE', 'hired', false, '{MINVALUE, ''2000-01-01''}'),
   ('partitions', 'employees', 'employees_2010', 'employees_2010', 'RANGE', 'hired', false, '{''2000-01-01'', ''2010-01-01''}'),
   ('partitions', 'employees', 'employees_2020', 'employees_2020', 'RANGE', 'hired', false, '{''2010-01-01'', ''2020-01-01''}'),
   ('partitions', 'employees', 'employees_default', 'employees_default', 'RANGE', 'hired', true, '{}');

/* perform the data migration */
SELECT db_migrate_mkforeign(
   plugin => 'mysql_migrator',
   server => 'mysql'
);

SELECT db_migrate_tables(
   plugin => 'mysql_migrator'
);

/* we have to check the log table before we drop the schema */
SELECT operation, schema_name, object_name, failed_sql, error_message
FROM pgsql_stage.migrate_log
ORDER BY log_time \gx

SELECT db_migrate_finish();

\d+ partitions.employees
\d+ partitions.employees_by_list
\d+ partitions.employees_by_int_range
\d+ partitions.employees_by_date_range
\d+ partitions.employees_by_hash

\d+ partitions.subpart_by_range_hash
\d+ partitions.subpart_less_than_1990
\d+ partitions.subpart_less_than_2000
\d+ partitions.subpart_less_than_max