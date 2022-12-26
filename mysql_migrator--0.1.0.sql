/* tools for MySQL/MariaDB to PostgreSQL migration */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION mysql_migrator" to load this file. \quit

CREATE FUNCTION mysql_create_catalog(
   server      name,
   schema      name    DEFAULT NAME 'public',
   options     jsonb   DEFAULT NULL
) RETURNS void
   LANGUAGE plpgsql VOLATILE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mysql_create_catalog$
DECLARE
   old_msglevel text;
   catalog_table varchar(64);
   catalog_tables varchar(64)[] := ARRAY[
      'SCHEMATA', 'TABLES', 'COLUMNS', 'TABLE_CONSTRAINTS', 'CHECK_CONSTRAINTS',
      'KEY_COLUMN_USAGE', 'REFERENTIAL_CONSTRAINTS', 'VIEWS', 'PARAMETERS',
      'STATISTICS', 'TABLE_PRIVILEGES', 'COLUMN_PRIVILEGES'
   ];
   sys_schemas text := $$ 'information_schema', 'mysql', 'performance_schema', 'sys' $$;

   /* schemas */
   schemas_sql text := $$
      CREATE OR REPLACE VIEW %1$I.schemas AS
         SELECT "SCHEMA_NAME" AS schema
         FROM %1$I."SCHEMATA"
         WHERE "SCHEMA_NAME" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.schemas IS 'MySQL schemas on foreign server "%3$I"';
   $$;

   /* tables */
   tables_sql text := $$      
      CREATE OR REPLACE VIEW %1$I.tables AS 
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name
         FROM %1$I."TABLES"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "TABLE_TYPE" = 'BASE TABLE';
      COMMENT ON VIEW %1$I.tables IS 'MySQL tables on foreign server "%3$I"';
   $$;

   /* columns */
   columns_sql text := $$      
      CREATE OR REPLACE VIEW %1$I.columns AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name,
            "COLUMN_NAME" AS column_name, "ORDINAL_POSITION" AS position,
            "DATA_TYPE" AS type_name, "CHARACTER_MAXIMUM_LENGTH" AS length,
            coalesce("NUMERIC_PRECISION", "DATETIME_PRECISION", null) AS precision,
            "NUMERIC_SCALE" AS scale, "IS_NULLABLE"::boolean AS nullable, 
            "COLUMN_DEFAULT" AS default_value
         FROM %1$I."COLUMNS"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.columns IS 'columns of MySQL tables and views on foreign server "%3$I"';
   $$;

   /* checks */
   check_sql text := $$
      CREATE OR REPLACE VIEW %1$I.checks AS
         SELECT "CONSTRAINT_SCHEMA" AS schema, "TABLE_SCHEMA" as table_name,
            "CONSTRAINT_NAME" AS constraint_name, false AS "deferrable", false AS deferred,
            "CHECK_CLAUSE" AS condition
         FROM %1$I."TABLE_CONSTRAINTS" cons
         JOIN %1$I."CHECK_CONSTRAINTS" cond USING ("CONSTRAINT_SCHEMA", "CONSTRAINT_NAME")
         WHERE "TABLE_SCHEMA" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.checks IS 'MySQL check constraints on foreign server "%3$I"';
   $$;

   /* foreign_keys */
   foreign_keys_sql text := $$
      CREATE OR REPLACE VIEW %1$I.foreign_keys AS
         SELECT "CONSTRAINT_SCHEMA" AS schema, "TABLE_NAME" AS table_name,
            "CONSTRAINT_NAME" AS constraint_name, false AS "deferrable", false AS deferred,
            "DELETE_RULE" AS delete_rule, "COLUMN_NAME" AS column_name, "ORDINAL_POSITION" AS position, 
            "REFERENCED_TABLE_SCHEMA" AS remote_schema, keys."REFERENCED_TABLE_NAME" AS remote_table,
            "REFERENCED_COLUMN_NAME" AS remote_column
         FROM %1$I."KEY_COLUMN_USAGE" keys
         JOIN %1$I."REFERENTIAL_CONSTRAINTS" refs USING ("CONSTRAINT_SCHEMA", "TABLE_NAME", "CONSTRAINT_NAME")
         WHERE "CONSTRAINT_SCHEMA" NOT IN (%2$s)
         AND "REFERENCED_COLUMN_NAME" IS NOT NULL;
      COMMENT ON VIEW %1$I.foreign_keys IS 'MySQL foreign key columns on foreign server "%3$I"';
   $$;

   /* keys */
   keys_sql text := $$
      CREATE OR REPLACE VIEW %1$I.keys AS
         SELECT "CONSTRAINT_SCHEMA" AS schema, "TABLE_NAME" AS table_name,
            (CASE WHEN "CONSTRAINT_NAME" = 'PRIMARY'
               THEN concat_ws('_', "TABLE_NAME", "COLUMN_NAME", 'pkey')
               ELSE "CONSTRAINT_NAME"
            END)::character varying(64) AS constraint_name, false AS "deferrable", false AS deferred,
            "COLUMN_NAME" AS column_name, "ORDINAL_POSITION" AS position, 
            ("CONSTRAINT_TYPE" = 'PRIMARY KEY') AS is_primary
         FROM %1$I."TABLE_CONSTRAINTS" cons
         JOIN %1$I."KEY_COLUMN_USAGE" keys USING ("CONSTRAINT_SCHEMA", "TABLE_NAME", "CONSTRAINT_NAME")
         WHERE "CONSTRAINT_SCHEMA" NOT IN (%2$s)
         AND "CONSTRAINT_TYPE" IN ('PRIMARY KEY', 'UNIQUE');
      COMMENT ON VIEW %1$I.keys IS 'MySQL primary and unique key columns on foreign server "%3$I"';
   $$;

   /* views */
   views_sql text := $$
      CREATE OR REPLACE VIEW %1$I.views AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS view_name,
            "VIEW_DEFINITION" AS definition
         FROM %1$I."VIEWS"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.views IS 'MySQL views on foreign server "%3$I"';
   $$;

   /* functions */
   functions_sql text := $$
      DROP FOREIGN TABLE IF EXISTS %1$I."ROUTINES" CASCADE;
      CREATE FOREIGN TABLE %1$I."ROUTINES" (
         "ROUTINE_SCHEMA" varchar(64) NOT NULL,
         "ROUTINE_NAME" varchar(64) NOT NULL,
         "ROUTINE_TYPE" varchar(10) NOT NULL,
         "DTD_IDENTIFIER" text,
         "ROUTINE_BODY" varchar(3) NOT NULL,
         "ROUTINE_DEFINITION" text,
         "EXTERNAL_LANGUAGE" varchar(64) NOT NULL,
         "IS_DETERMINISTIC" varchar(3) NOT NULL
      ) SERVER %3$I OPTIONS (dbname 'information_schema', table_name 'ROUTINES');

      CREATE OR REPLACE VIEW %1$I.functions AS
         SELECT "ROUTINE_SCHEMA" AS schema, "ROUTINE_NAME" AS function_name,
            ("ROUTINE_TYPE" = 'PROCEDURE') AS is_procedure,
            (CASE "ROUTINE_TYPE" 
               WHEN 'PROCEDURE' THEN
                  concat_ws(' ', 
                     'CREATE PROCEDURE', "ROUTINE_NAME", '(', parameters, ')', 
                     "ROUTINE_DEFINITION"
                  )
               WHEN 'FUNCTION' THEN
                  concat_ws(' ', 
                     'CREATE FUNCTION', "ROUTINE_NAME", '(', parameters, ')', 
                     'RETURNS', "DTD_IDENTIFIER", 
                     "ROUTINE_DEFINITION"
                  )
               END
            ) AS source
         FROM %1$I."ROUTINES" rout
         JOIN (
            SELECT "SPECIFIC_SCHEMA" AS "ROUTINE_SCHEMA", "SPECIFIC_NAME" AS "ROUTINE_NAME",
               string_agg(
                  concat_ws(' ', "PARAMETER_MODE", "PARAMETER_NAME", "DTD_IDENTIFIER"),
                  text ', ' ORDER BY "ORDINAL_POSITION"
               ) AS parameters
            FROM %1$I."PARAMETERS"
            WHERE "ORDINAL_POSITION" > 0
            GROUP BY "SPECIFIC_SCHEMA", "SPECIFIC_NAME"
         ) prms USING ("ROUTINE_SCHEMA", "ROUTINE_NAME")
         WHERE "ROUTINE_SCHEMA" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.functions IS 'MySQL functions and procedures on foreign server "%3$I"';
   $$;

   /* sequences */
   sequences_sql text := $$
      CREATE OR REPLACE VIEW %1$I.sequences AS
         SELECT "TABLE_SCHEMA" AS schema, concat("TABLE_NAME", '_seq') AS sequence_name,
            1 AS "min_value", null::integer AS max_value, 1 AS increment_by, false AS cyclical,
            1 AS cache_size, "AUTO_INCREMENT" AS last_value
         FROM %1$I."TABLES" 
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "TABLE_TYPE" = 'BASE TABLE' AND "AUTO_INCREMENT" IS NOT NULL;
      COMMENT ON VIEW %1$I.sequences IS 'MySQL sequences on foreign server "%3$I"';
   $$;

   /* index_columns */
   index_columns_sql text := $$
      CREATE OR REPLACE VIEW %1$I.index_columns AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name, 
            concat_ws('_', "TABLE_NAME", "INDEX_NAME")::character varying(64) AS index_name, 
            "SEQ_IN_INDEX" AS position, (CASE WHEN "COLLATION" = 'D' THEN true ELSE false END) AS descend,
            "EXPRESSION" IS NOT NULL 
               AND ("COLLATION" <> 'D' OR "EXPRESSION" !~ '^`[^`]*`$') AS is_expression,
            coalesce(
               CASE WHEN "COLLATION" = 'D' AND "EXPRESSION" !~ '^`[^`]*`$'
                  THEN replace ("EXPRESSION", '`', '''')
                  ELSE "EXPRESSION"
               END, "COLUMN_NAME")::character varying(64) AS column_name
         FROM %1$I."STATISTICS"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "INDEX_NAME" <> 'PRIMARY' AND "IS_VISIBLE"::boolean; -- prior to MySQL v8
      COMMENT ON VIEW %1$I.index_columns IS 'MySQL index columns on foreign server "%3$I"';
   $$;
   
   /* indexes */
   indexes_sql text := $$
      CREATE OR REPLACE VIEW %1$I.indexes AS
         SELECT DISTINCT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name,
            concat_ws('_', "TABLE_NAME", "INDEX_NAME")::character varying(64) AS index_name, 
            "INDEX_TYPE" AS index_type, ("NON_UNIQUE" = 0) AS uniqueness
         FROM %1$I."STATISTICS"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "INDEX_NAME" <> 'PRIMARY' AND "IS_VISIBLE"::boolean; -- prior to MySQL v8
      COMMENT ON VIEW %1$I.indexes IS 'MySQL indexes on foreign server "%3$I"';
   $$;

   /* triggers */   
   triggers_sql text := $$
      DROP FOREIGN TABLE IF EXISTS %1$I."TRIGGERS" CASCADE;
      CREATE FOREIGN TABLE %1$I."TRIGGERS" (
         "TRIGGER_SCHEMA" varchar(64) NOT NULL,
         "TRIGGER_NAME" varchar(64) NOT NULL,
         "EVENT_MANIPULATION" varchar(6) NOT NULL,
         "EVENT_OBJECT_TABLE" varchar(64) NOT NULL,
         "ACTION_STATEMENT" text NOT NULL,
         "ACTION_ORIENTATION" varchar(3) NOT NULL,
         "ACTION_TIMING" varchar(6) NOT NULL
      ) SERVER %3$I OPTIONS (dbname 'information_schema', table_name 'TRIGGERS');

      CREATE OR REPLACE VIEW %1$I.triggers AS
         SELECT "TRIGGER_SCHEMA" AS schema, "EVENT_OBJECT_TABLE" AS table_name, 
            "TRIGGER_NAME" AS trigger_name, "ACTION_TIMING" AS trigger_type,
            "EVENT_MANIPULATION" AS triggering_event,
            ("ACTION_ORIENTATION" = 'ROW') AS for_each_row, null AS when_clause, 
            'REFERENCING NEW AS NEW OLD AS OLD' AS referencing_names,
            "ACTION_STATEMENT" AS trigger_body
         FROM %1$I."TRIGGERS"
         WHERE "TRIGGER_SCHEMA" NOT IN (%2$s);
      COMMENT ON VIEW %1$I.triggers IS 'MySQL triggers on foreign server "%3$I"';
   $$;

   /* packages -- not available */
   packages_sql text := $$
      CREATE OR REPLACE VIEW %1$I.packages AS
         SELECT null::varchar(64) AS schema, null::varchar(64) AS package_name,
            false AS is_body, null AS source
         WHERE 1 = 0;
      COMMENT ON VIEW %1$I.packages IS 'MySQL does not have packages';
   $$;

   /* table_privs */
   table_privs_sql text := $$
      CREATE OR REPLACE VIEW %1$I.table_privs AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name, 
            "PRIVILEGE_TYPE" AS privilege, 'root'::varchar(292) AS grantor,
            "GRANTEE" as grantee, "IS_GRANTABLE"::boolean AS grantable
         FROM %1$I."TABLE_PRIVILEGES"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s) AND "GRANTEE" !~ 'root';
      COMMENT ON VIEW %1$I.table_privs IS 'Privileges on MySQL tables on foreign server "%3$I"';
   $$;

   /* column_privs */
   column_privs_sql text := $$
      CREATE OR REPLACE VIEW %1$I.column_privs AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS table_name,
            "COLUMN_NAME" AS column_name, "PRIVILEGE_TYPE" AS privilege,
            'root'::varchar(292) AS grantor, "GRANTEE" AS grantee, "IS_GRANTABLE"::boolean AS grantable
         FROM %1$I."COLUMN_PRIVILEGES"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s) AND "GRANTEE" !~ 'root';
      COMMENT ON VIEW %1$I.column_privs IS 'Privileges on MySQL table columns on foreign server "%3$I"';
   $$;

   /* segments */
   segments_sql text := $$
      DROP FOREIGN TABLE IF EXISTS %1$I.innodb_index_stats CASCADE;
      CREATE FOREIGN TABLE %1$I.innodb_index_stats (
         database_name varchar(64) NOT NULL,
         table_name varchar(64) NOT NULL,
         index_name varchar(64) NOT NULL,
         stat_value bigint NOT NULL,
         stat_description varchar(1024) NOT NULL
      ) SERVER %3$I OPTIONS (dbname 'mysql', table_name 'innodb_index_stats');

      CREATE OR REPLACE VIEW %1$I.segments AS
         SELECT "TABLE_SCHEMA" AS schema, "TABLE_NAME" AS segment_name,
            'TABLE' AS segment_type, "DATA_LENGTH" AS bytes
         FROM %1$I."TABLES"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "TABLE_TYPE" = 'BASE TABLE'
         UNION
         SELECT "TABLE_SCHEMA", "TABLE_NAME" segment_name,
            'INDEX' AS segment_name, "INDEX_LENGTH" AS bytes
         FROM %1$I."TABLES"
         WHERE "TABLE_SCHEMA" NOT IN (%2$s)
         AND "TABLE_TYPE" = 'BASE TABLE' AND "ENGINE" = 'MyISAM'
         UNION 
         SELECT database_name, index_name, 'INDEX' AS segment_type,
            sum(stat_value) * 16384 AS bytes
         FROM %1$I.innodb_index_stats
         WHERE database_name NOT IN (%2$s)
         AND index_name <> 'PRIMARY'
         AND stat_description LIKE 'Number of pages in the index'
         GROUP BY database_name, index_name;
      COMMENT ON VIEW %1$I.segments IS 'Size of MySQL objects on foreign server "%3$I"';
   $$;

   /* migration_cost_estimate */
   migration_cost_estimate_sql text := $$
      CREATE VIEW %1$I.migration_cost_estimate AS
         SELECT schema, 'tables'::text AS task_type, count(*)::bigint AS task_content,
            'count'::text AS task_unit, ceil(count(*) / 10.0)::integer AS migration_hours
         FROM %1$I.tables GROUP BY schema
         UNION ALL
         SELECT t.schema, 'data_migration'::text, sum(bytes)::bigint,
            'bytes'::text, ceil(sum(bytes::float8) / 26843545600.0)::integer
         FROM %1$I.segments AS s
         JOIN %1$I.tables AS t ON s.schema = t.schema AND s.segment_name = t.table_name
         WHERE s.segment_type = 'TABLE' 
         GROUP BY t.schema
         UNION ALL
         SELECT schema, 'functions'::text, coalesce(sum(octet_length(source)), 0),
            'characters'::text, ceil(coalesce(sum(octet_length(source)), 0) / 512.0)::integer
         FROM %1$I.functions GROUP BY schema
         UNION ALL
         SELECT schema, 'triggers'::text, coalesce(sum(octet_length(trigger_body)), 0),
            'characters'::text, ceil(coalesce(sum(octet_length(trigger_body)), 0) / 512.0)::integer
         FROM %1$I.triggers GROUP BY schema
         UNION ALL
         SELECT schema, 'views'::text, coalesce(sum(octet_length(definition)), 0),
            'characters'::text, ceil(coalesce(sum(octet_length(definition)), 0) / 512.0)::integer
         FROM %1$I.views GROUP BY schema;
      COMMENT ON VIEW %1$I.migration_cost_estimate IS 'Estimate of the migration costs per schema and object type';
   $$;

   /* test_error */
   test_error_sql text := $$
      CREATE TABLE %1$I.test_error (
         log_time timestamp with time zone NOT NULL DEFAULT current_timestamp,
         schema name NOT NULL,
         table_name name NOT NULL,
         rowid text NOT NULL,
         message text NOT NULL,
         PRIMARY KEY (schema, table_name, log_time, rowid)
      );
      COMMENT ON TABLE %1$I.test_error IS 'Errors from the last run of "mysql_migrate_test_data"';
   $$;

   /* test_error_stats */
   test_error_stats_sql text := $$
      CREATE TABLE %1$I.test_error_stats (
         log_time timestamp with time zone NOT NULL,
         schema name NOT NULL,
         table_name name NOT NULL,
         errcount bigint NOT NULL,
         PRIMARY KEY (schema, table_name, log_time)
      );
      COMMENT ON TABLE %1$I.test_error IS 'Cumulative errors from previous runs of "mysql_migrate_test_data"';
   $$;
   
BEGIN
   /* remember old setting */
   old_msglevel := current_setting('client_min_messages');

   /* make the output less verbose */
   SET LOCAL client_min_messages = warning;

   /* refresh catalog foreign tables */
   FOREACH catalog_table IN ARRAY catalog_tables
   LOOP
      EXECUTE format(
         $$ DROP FOREIGN TABLE IF EXISTS %1$I.%2$I CASCADE $$,
         schema, catalog_table
      );

      EXECUTE format(
         $$ IMPORT FOREIGN SCHEMA information_schema 
         LIMIT TO (%3$I) 
         FROM SERVER %1$I INTO %2$I
         OPTIONS (import_enum_as_text 'true') $$,
         server, schema, catalog_table
      );      
   END LOOP;

   /* create views with predefined column names needed by db_migrator */
   EXECUTE format(schemas_sql, schema, sys_schemas, server);
   EXECUTE format(tables_sql, schema, sys_schemas, server);
   EXECUTE format(columns_sql, schema, sys_schemas, server);
   EXECUTE format(check_sql, schema, sys_schemas, server);
   EXECUTE format(foreign_keys_sql, schema, sys_schemas, server);
   EXECUTE format(keys_sql, schema, sys_schemas, server);
   EXECUTE format(views_sql, schema, sys_schemas, server);
   EXECUTE format(functions_sql, schema, sys_schemas, server);
   EXECUTE format(sequences_sql, schema, sys_schemas, server);
   EXECUTE format(index_columns_sql, schema, sys_schemas, server);
   EXECUTE format(indexes_sql, schema, sys_schemas, server);
   EXECUTE format(triggers_sql, schema, sys_schemas, server);
   EXECUTE format(packages_sql, schema);
   EXECUTE format(table_privs_sql, schema, sys_schemas, server);
   EXECUTE format(column_privs_sql, schema, sys_schemas, server);
   EXECUTE format(segments_sql, schema, sys_schemas, server);
   EXECUTE format(migration_cost_estimate_sql, schema);
   EXECUTE format(test_error_sql, schema);
   EXECUTE format(test_error_stats_sql, schema);

   /* reset client_min_messages */
   EXECUTE 'SET LOCAL client_min_messages = ' || old_msglevel;
END;
$mysql_create_catalog$;

COMMENT ON FUNCTION mysql_create_catalog(name, name, jsonb) IS
   'create MySQL foreign tables for the metadata of a foreign server';

CREATE FUNCTION mysql_mkforeign(
   server         name,
   schema         name,
   table_name     name,
   orig_schema    text,
   orig_table     text,
   column_names   name[],
   column_options jsonb[],
   orig_columns   text[],
   data_types     text[],
   nullable       boolean[],
   options        jsonb
) RETURNS text
   LANGUAGE plpgsql IMMUTABLE CALLED ON NULL INPUT AS
$mysql_mkforeign$
DECLARE
   stmt       text;
   i          integer;
   sep        text := '';
   colopt_str text;
BEGIN
   stmt := format(E'CREATE FOREIGN TABLE %I.%I (', schema, table_name);

   FOR i IN 1..cardinality(column_names) LOOP
      /* format the column options as string */
      SELECT ' OPTIONS (' ||
             string_agg(format('%I %L', j.key, j.value->>0), ', ') ||
             ')'
         INTO colopt_str
      FROM jsonb_each(column_options[i]) AS j;

      stmt := stmt || format(E'%s\n   %I %s%s%s',
                         sep, column_names[i], data_types[i],
                         coalesce(colopt_str, ''),
                         CASE WHEN nullable[i] THEN '' ELSE ' NOT NULL' END
                      );
      sep := ',';
   END LOOP;

   RETURN stmt || format(
                     E') SERVER %I\n'
                     '   OPTIONS (dbname ''%s'', table_name ''%s'', max_blob_size ''%s'')',
                     server, orig_schema, orig_table,
                     CASE WHEN options ? 'max_blob_size'
                          THEN (options->>'max_blob_size')::bigint
                          ELSE 32767
                     END
                  );
END;
$mysql_mkforeign$;

COMMENT ON FUNCTION mysql_mkforeign(name,name,name,text,text,name[],jsonb[],text[],text[],boolean[],jsonb) IS
   'construct a CREATE FOREIGN TABLE statement based on the input data';

CREATE FUNCTION mysql_translate_datatype(
   v_type text,
   v_length integer,
   v_precision integer,
   v_scale integer
) RETURNS text
   LANGUAGE plpgsql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mysql_translate_datatype$
DECLARE
   v_geom_type text;
BEGIN
   /* get the postgis geometry type if it exists */
   SELECT extnamespace::regnamespace::text || '.geometry' INTO v_geom_type
      FROM pg_catalog.pg_extension
      WHERE extname = 'postgis';
   IF v_geom_type IS NULL THEN v_geom_type := 'text'; END IF;
   
   /* get the PostgreSQL type */
   CASE
      -- numeric types
      -- 
      WHEN v_type IN ('TINYINT UNSIGNED', 'TINYINT', 'SMALLINT', 'YEAR') THEN RETURN 'smallint';
      WHEN v_type IN ('SMALLINT UNSIGNED', 'MEDIUMINT UNSIGNED', 'MEDIUMINT', 'INT') THEN RETURN 'integer';
      WHEN v_type IN ('INT UNSIGNED', 'BIGINT', 'UNSIGNED') THEN RETURN 'bigint';
      WHEN v_type IN ('DECIMAL', 'DEC') THEN RETURN 'decimal';
      WHEN v_type IN ( 'FLOAT', 'DOUBLE PRECISION', 'DOUBLE') THEN RETURN 'double precision';
      WHEN v_type IN ('BIGINT UNSIGNED', 'NUMERIC', 'FIXED') THEN RETURN 'numeric';
      WHEN v_type IN ('REAL') THEN RETURN 'real';

      -- text types
      --
      WHEN v_type IN ('TINYTEXT', 'TEXT', 'MEDIUMTEXT', 'LONGTEXT', 'ENUM', 'SET') THEN RETURN 'text';
      WHEN v_type IN ('CHAR') THEN RETURN 'char';
      WHEN v_type IN ('VARCHAR') THEN RETURN 'varchar';

      -- date types
      --
      WHEN v_type IN ('DATETIME', 'TIMESTAMP') THEN RETURN 'timestamp without time zone';
      WHEN v_type IN ('TIME') THEN RETURN 'time without time zone';
      WHEN v_type IN ('DATE') THEN RETURN 'date';

      -- binary types
      WHEN v_type IN ('VARBINARY', 'BINARY', 'TINYBLOB', 'BLOB', 'MEDIUMBLOB', 'LONGBLOB') THEN RETURN 'bytea';
      WHEN v_type IN ('BIT') THEN RETURN 'bit varying';

      -- other types
      WHEN v_type IN ('BOOLEAN', 'BOOL') THEN RETURN 'boolean';
      WHEN v_type IN ('MULTIPOLYGON') THEN RETURN v_geom_type;

      -- cannot translate
      ELSE RETURN 'text'; 
   END CASE;
END;
$mysql_translate_datatype$;

COMMENT ON FUNCTION mysql_translate_datatype(text,integer,integer,integer) IS
   'translates an MySQL data type to a PostgreSQL data type';

CREATE FUNCTION mysql_translate_identifier_noop(text) RETURNS name
   LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mysql_translate_identifier_noop$
SELECT $1
$mysql_translate_identifier_noop$;

COMMENT ON FUNCTION mysql_translate_identifier_noop(text) IS
   'helper noop function for MySQL names';

CREATE FUNCTION mysql_translate_expression(s text) RETURNS text
   LANGUAGE plpgsql IMMUTABLE STRICT SET search_path FROM CURRENT AS
$mysql_translate_expression$
BEGIN
   RETURN s;
END;
$mysql_translate_expression$;

COMMENT ON FUNCTION mysql_translate_expression(text) IS
   'helper function to translate MySQL expressions to PostgreSQL';

CREATE FUNCTION db_migrator_callback(
   OUT create_metadata_views_fun regprocedure,
   OUT translate_datatype_fun    regprocedure,
   OUT translate_identifier_fun  regprocedure,
   OUT translate_expression_fun  regprocedure,
   OUT create_foreign_table_fun  regprocedure
) RETURNS record
   LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$db_migrator_callback$
WITH ext AS (
   SELECT extnamespace::regnamespace::text AS schema_name
   FROM pg_extension
   WHERE extname = 'mysql_migrator'
)
SELECT format('%s.%I(name,name,jsonb)', ext.schema_name, 'mysql_create_catalog')::regprocedure,
       format('%s.%I(text,integer,integer,integer)', ext.schema_name, 'mysql_translate_datatype')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mysql_translate_identifier_noop')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mysql_translate_expression')::regprocedure,
       format('%s.%I(name,name,name,text,text,name[],jsonb[],text[],text[],boolean[],jsonb)', ext.schema_name, 'mysql_mkforeign')::regprocedure
FROM ext
$db_migrator_callback$;

COMMENT ON FUNCTION db_migrator_callback() IS
   'callback for db_migrator to get the appropriate conversion functions';