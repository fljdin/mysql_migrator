/* connect as migration user */
\connect - migrator
SET client_min_messages = WARNING;

/* we have to check the log table before we drop the schema */
SELECT operation, schema_name, object_name, failed_sql, error_message
FROM pgsql_stage.migrate_log
ORDER BY log_time \gx

SELECT db_migrate_finish();