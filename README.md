MySQL/MariaDB to PostgreSQL migration tools
===========================================

`mysql_migrator` is a plugin for [`db_migrator`][migrator] that uses
[`mysql_fdw`][mysql_fdw] to migrate an MySQL or MariaDB database to PostgreSQL.

 [migrator]: https://github.com/cybertec-postgresql/db_migrator
 [mysql_fdw]: https://github.com/EnterpriseDB/mysql_fdw


Prerequisites
=============

- You need PostgreSQL 10 or later.

- The `mysql_fdw` and `db_migrator` extensions must be installed.

- A foreign server must be defined for the MySQL database you want to access.

- A user mapping must exist for the user who calls the `db_migrate` function.

Objects created by the extension
================================

Migration functions
-------------------

The `db_migrator` callback function `db_migrator_callback()` returns the
migration functions provided by the extension.
See the `db_migrator` documentation for details.

### function `mysql_migrate_identity`

This function must be executed after `db_migrate_mkforeign()`, as it replaces
pre-existent sequences. 

Its read `tables`, `columns`, `keys` and `sequences` staging tables to correctly
map primary key columns with MySQL's `AUTO_INCREMENT` attribute, in order to
define identity specifications per column.

The function parameters are:

- `pgstage_schema` (default `pgsql_stage`): The name of the PostgreSQL stage
  created by `db_migrate_prepare()`