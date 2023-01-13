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
