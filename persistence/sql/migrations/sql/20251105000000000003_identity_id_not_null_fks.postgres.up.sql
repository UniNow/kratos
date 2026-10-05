-- UniNow: fill and constrain atomically.
--
-- The backfills in 20251105000000000001/2 are recorded as applied once they
-- finish, so they never run again. On a rolling upgrade the previous release is
-- still serving while they run, and it predates the identity_id column, so it
-- keeps writing NULL into both tables. By the time the statements below run,
-- fresh NULL rows exist again and SET NOT NULL fails - which blocks the new
-- pods from ever starting, so the old ones keep serving and keep producing
-- NULLs. The rollout then never completes on its own.
--
-- Taking the lock first closes that window: no writer can insert between the
-- fill and the constraint, because this whole file runs in one transaction.
-- lock_timeout keeps a contended lock from queueing writers indefinitely; the
-- migration simply fails and is retried instead.

SET LOCAL lock_timeout = '10s';

LOCK TABLE identity_credential_identifiers IN ACCESS EXCLUSIVE MODE;
LOCK TABLE session_devices IN ACCESS EXCLUSIVE MODE;

UPDATE identity_credential_identifiers ici
SET identity_id = ic.identity_id
FROM identity_credentials ic
WHERE ici.identity_credential_id = ic.id
  AND ici.nid = ic.nid
  AND ici.identity_id IS NULL;

UPDATE session_devices sd
SET identity_id = s.identity_id
FROM sessions s
WHERE sd.session_id = s.id
  AND sd.nid = s.nid
  AND sd.identity_id IS NULL;

ALTER TABLE identity_credential_identifiers
    ALTER identity_id SET NOT NULL,
    ADD CONSTRAINT "identity_credential_identifiers_identities_id_fk" FOREIGN KEY (identity_id) REFERENCES identities (id) ON UPDATE RESTRICT ON DELETE CASCADE;


ALTER TABLE session_devices
    ALTER identity_id SET NOT NULL,
    ADD CONSTRAINT "session_devices_identities_id_fk" FOREIGN KEY (identity_id) REFERENCES identities (id) ON UPDATE RESTRICT ON DELETE CASCADE;
