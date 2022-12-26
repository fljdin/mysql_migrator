MySQL/MariaDB to PostgreSQL migration tools
===========================================

`mysql_migrator` is a plugin for [`db_migrator`][migrator] that uses
[`mysql_fdw`][mysql_fdw] to migrate an MySQL or MariaDB database to PostgreSQL.

 [migrator]: https://github.com/cybertec-postgresql/db_migrator
 [mysql_fdw]: https://github.com/EnterpriseDB/mysql_fdw


Prerequisites
=============

- You need PostgreSQL 9.5 or later.

- The `mysql_fdw` and `db_migrator` extensions must be installed.
