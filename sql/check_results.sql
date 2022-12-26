SET client_min_messages = WARNING;

\dn

\d fdw_stage.*

SELECT * FROM fdw_stage.schemas ORDER BY schema;
SELECT * FROM fdw_stage.tables ORDER BY schema, table_name;
SELECT * FROM fdw_stage.columns ORDER BY schema, table_name, position;
SELECT * FROM fdw_stage.checks ORDER BY schema, table_name, constraint_name;
SELECT * FROM fdw_stage.foreign_keys ORDER BY schema, table_name, constraint_name, position;
SELECT * FROM fdw_stage.keys ORDER BY schema, table_name, position;
SELECT * FROM fdw_stage.views ORDER BY schema, view_name;
SELECT * FROM fdw_stage.functions ORDER BY schema, function_name;
SELECT * FROM fdw_stage.sequences ORDER BY schema, sequence_name;
SELECT * FROM fdw_stage.index_columns ORDER BY schema, table_name, index_name, position;
SELECT * FROM fdw_stage.indexes ORDER BY schema, table_name, index_name;
SELECT * FROM fdw_stage.triggers ORDER BY schema, table_name, trigger_name;
SELECT * FROM fdw_stage.packages;
SELECT * FROM fdw_stage.table_privs ORDER BY schema, table_name, privilege;
SELECT * FROM fdw_stage.column_privs ORDER BY schema, table_name, privilege;
SELECT * FROM fdw_stage.segments ORDER BY schema, segment_name, segment_type;
SELECT * FROM fdw_stage.migration_cost_estimate ORDER BY schema, task_type;