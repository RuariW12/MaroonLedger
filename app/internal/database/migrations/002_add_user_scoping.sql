-- Scope every account to the identity that owns it.
-- user_id holds the Cognito `sub` claim. It is TEXT rather than UUID so the
-- schema does not depend on the identity provider's identifier format.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS user_id TEXT;

-- Rows created before authentication existed have no owner. Park them under a
-- sentinel so NOT NULL can be applied without dropping data -- no Cognito sub
-- can collide with this value, so the rows stay unreachable through the API.
UPDATE accounts SET user_id = 'legacy-unowned' WHERE user_id IS NULL;

ALTER TABLE accounts ALTER COLUMN user_id SET NOT NULL;

-- Every account read filters on user_id, so this index backs the hot path.
CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON accounts(user_id);
