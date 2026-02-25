-- Suggested fix: replace expression-based index `ix_products_performance2`
-- Original expression: CASE WHEN parent_product_id IS NULL THEN id ELSE parent_product_id END
-- MariaDB cannot index expressions directly; create a STORED generated column and index it.

-- 1) Add generated column (best placed after `parent_product_id` column)
ALTER TABLE products
  ADD COLUMN parent_or_self_id INT
    GENERATED ALWAYS AS (COALESCE(parent_product_id, id)) STORED;

-- 2) Create the index on the generated column plus `active` as in original index
CREATE INDEX ix_products_performance2 ON products (parent_or_self_id, active);

-- 3) (Optional) After verifying correctness and data/import, you may drop the old index
-- (if present in the target DB) with:
-- DROP INDEX ix_products_performance2 ON products;

-- Notes:
-- - Ensure the generated column type (`INT`) matches the real PK/foreign key types used.
-- - If `id` or `parent_product_id` are UNSIGNED in the target DDL, declare the generated
--   column as `INT UNSIGNED` accordingly.
-- - If your dataset is large, add the generated column and build the index during low-traffic time.
