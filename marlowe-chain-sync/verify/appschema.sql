-- Verify chain:appschema on pg

BEGIN;

SELECT pg_catalog.has_schema_privilege('chain', 'usage');

ROLLBACK;
