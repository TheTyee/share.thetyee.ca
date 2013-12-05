-- Verify schema

BEGIN;

    SELECT pg_catalog.has_schema_privilege('shares', 'usage');

ROLLBACK;
