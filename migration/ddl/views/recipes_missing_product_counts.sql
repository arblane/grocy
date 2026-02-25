-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW recipes_missing_product_counts AS
SELECT
	recipe_id,
	COUNT(*) AS missing_products_count
FROM recipes_pos_resolved
WHERE need_fulfilled = 0
GROUP BY recipe_id;;
