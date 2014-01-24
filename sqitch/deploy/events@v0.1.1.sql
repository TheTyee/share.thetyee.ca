-- Deploy events

BEGIN;

    SET client_min_messages = 'warning';

    CREATE TABLE shares.event ( 
        id serial PRIMARY KEY,
        email_from TEXT NOT NULL,
        email_to   TEXT NOT NULL,
        url        TEXT NOT NULL,
        title      TEXT NOT NULL,
        summary    TEXT NOT NULL,
        img        TEXT NOT NULL,
        message    TEXT NOT NULL,
        timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        wc_sub_pref TEXT NOT NULL,
        wc_result_send  TEXT NULL,
        wc_result_sub  TEXT NULL,
        UNIQUE( email_from, email_to, url, message )
    );

COMMIT;
