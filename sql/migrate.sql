/* connect as migration user */
\connect - migrator
SET client_min_messages = WARNING;

/* set up staging schemas */
SELECT db_migrate_prepare(
   plugin => 'mysql_migrator',
   server => 'mysql',
   only_schemas => '{sakila}'
);

/* exclude bytea columns from migration */
DELETE FROM pgsql_stage.columns WHERE type_name = 'bytea';

/* quote character expression */
UPDATE pgsql_stage.columns 
   SET default_value = quote_literal(default_value)
   WHERE NOT regexp_like(default_value, '^\-?[0-9]+$')
   AND default_value <> 'CURRENT_TIMESTAMP';

/* disable view migration */
UPDATE pgsql_stage.views SET migrate = false;

/* perform the data migration */
SELECT db_migrate_mkforeign(
   plugin => 'mysql_migrator',
   server => 'mysql'
);

/* migrate the rest of the database */
SELECT db_migrate_tables(
   plugin => 'mysql_migrator'
);

SELECT db_migrate_functions(
   plugin => 'mysql_migrator'
);

SELECT db_migrate_triggers(
   plugin => 'mysql_migrator'
);

SELECT db_migrate_views(
   plugin => 'mysql_migrator'
);

SELECT db_migrate_indexes(
   plugin => 'mysql_migrator'
);

SELECT db_migrate_constraints(
   plugin => 'mysql_migrator'
);

/* attach sequences to table columns as identity */
SELECT mysql_migrate_identity();