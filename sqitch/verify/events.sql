-- Verify events

BEGIN;

SELECT id, email_to, email_from, wc_result_send, wc_result_sub, wc_sub_pref, url, title, summary, img, message, timestamp
  FROM shares.event
 WHERE FALSE;

ROLLBACK;
