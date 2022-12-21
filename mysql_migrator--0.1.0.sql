/* tools for MySQL/MariaDB to PostgreSQL migration */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION mysql_migrator" to load this file. \quit

CREATE FUNCTION mysql_translate_datatype(
   v_type text,
   v_length integer,
   v_precision integer,
   v_scale integer
) RETURNS text
   LANGUAGE plpgsql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$$DECLARE
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
END;$$;

COMMENT ON FUNCTION mysql_translate_datatype(text,integer,integer,integer) IS
   'translates an MySQL data type to a PostgreSQL data type';

CREATE FUNCTION db_migrator_callback(
   OUT create_metadata_views_fun regprocedure,
   OUT translate_datatype_fun    regprocedure,
   OUT translate_identifier_fun  regprocedure,
   OUT translate_expression_fun  regprocedure,
   OUT create_foreign_table_fun  regprocedure
) RETURNS record
   LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$$WITH ext AS (
   SELECT extnamespace::regnamespace::text AS schema_name
   FROM pg_extension
   WHERE extname = 'mysql_migrator'
)
SELECT format('%s.%I(name,name,jsonb)', ext.schema_name, 'mysql_create_catalog')::regprocedure,
       format('%s.%I(text,integer,integer,integer)', ext.schema_name, 'mysql_translate_datatype')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mysql_tolower')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mysql_translate_expression')::regprocedure,
       format('%s.%I(name,name,name,text,text,name[],jsonb[],text[],text[],boolean[],jsonb)', ext.schema_name, 'mysql_mkforeign')::regprocedure
FROM ext$$;

COMMENT ON FUNCTION db_migrator_callback() IS
   'callback for db_migrator to get the appropriate conversion functions';