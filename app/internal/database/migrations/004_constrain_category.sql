-- Close the category set at the database level.
--
-- Application validation now rejects an unlisted category, but rows written
-- before that check existed can still hold arbitrary text, and a future code
-- path could reintroduce the gap. The analytics layer treats this set as
-- closed -- Athena projects partitions from exactly these twelve values -- so a
-- row outside it is stored successfully and then silently missing from every
-- query. A constraint is the only thing that makes the invariant true rather
-- than merely intended.

-- Repair first: anything already outside the set becomes 'other', which is the
-- same fallback the model path uses. Nothing is deleted -- the amount, date and
-- description are unaffected, only the label changes.
UPDATE transactions
SET category = 'other'
WHERE category NOT IN (
    'groceries', 'dining', 'transport', 'housing', 'utilities', 'healthcare',
    'entertainment', 'shopping', 'income', 'transfer', 'fees', 'other'
);

-- Normalise case and whitespace while we are here; the application lowercases
-- and trims on write, but older rows predate that.
UPDATE transactions
SET category = lower(btrim(category))
WHERE category <> lower(btrim(category));

ALTER TABLE transactions
    DROP CONSTRAINT IF EXISTS transactions_category_check;

ALTER TABLE transactions
    ADD CONSTRAINT transactions_category_check CHECK (
        category IN (
            'groceries', 'dining', 'transport', 'housing', 'utilities', 'healthcare',
            'entertainment', 'shopping', 'income', 'transfer', 'fees', 'other'
        )
    );
