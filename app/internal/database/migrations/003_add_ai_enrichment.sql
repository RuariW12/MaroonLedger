-- Records what the AI layer concluded about each transaction.
--
-- These columns are all nullable or defaulted: enrichment is best-effort, and a
-- transaction whose analysis failed is still a valid transaction. Nothing in
-- the write path depends on them being populated.

-- True when the category came from the model rather than the user, so the UI
-- can distinguish a suggestion from a stated fact.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS auto_categorized BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS anomaly_severity TEXT
    CHECK (anomaly_severity IN ('none', 'low', 'medium', 'high'));

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS anomaly_reason TEXT;

-- Which provider produced the enrichment ('bedrock' or 'stub'). Recorded so
-- output from the local stub is never mistaken for real model inference.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS ai_provider TEXT;

-- Supports the "show me what needs attention" query without scanning the table.
CREATE INDEX IF NOT EXISTS idx_transactions_anomaly
    ON transactions(account_id, anomaly_severity)
    WHERE anomaly_severity IN ('medium', 'high');
