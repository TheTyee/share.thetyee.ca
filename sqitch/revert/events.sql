-- Deploy events

BEGIN;

    SET client_min_messages = 'warning';
    
    ALTER TABLE shares.event DROP COLUMN wc_status;

COMMIT;
