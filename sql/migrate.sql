/*
 * Test migration from MySQL.
 */

SET client_min_messages = WARNING;

/* create a user to perform the migration */
DROP ROLE IF EXISTS migrator;
CREATE ROLE migrator LOGIN;

/* create all requisite extensions */
CREATE EXTENSION mysql_fdw;
CREATE EXTENSION mysql_migrator CASCADE;

/* create a foreign server and a user mapping */
CREATE SERVER mysql FOREIGN DATA WRAPPER mysql_fdw
   OPTIONS (host 'mysql_db', fetch_size '1000');

CREATE USER MAPPING FOR PUBLIC SERVER mysql
   OPTIONS (username 'root', password 'p_ssW0rd');

/* give the user the required permissions */
GRANT CREATE ON DATABASE contrib_regression TO migrator;
GRANT USAGE ON FOREIGN SERVER mysql TO migrator;

/* connect as migration user */
\connect - migrator
SET client_min_messages = WARNING;

/* set up staging schemas */
SELECT db_migrate_prepare(
   plugin => 'mysql_migrator',
   server => 'mysql'
);

/* exclude bytea columns from migration */
DELETE FROM pgsql_stage.columns WHERE type_name = 'bytea';

/* quote character expression */
UPDATE pgsql_stage.columns SET default_value = $$'G'$$
   WHERE default_value = 'G';

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

SELECT db_migrate_constraints(
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