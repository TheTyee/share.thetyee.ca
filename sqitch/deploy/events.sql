-- Deploy events

BEGIN;

    SET client_min_messages = 'warning';

    ALTER TABLE shares.event ADD COLUMN wc_status TEXT NULL;

COMMIT;
