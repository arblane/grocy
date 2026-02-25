-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW recipes_resolved AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	r.id AS recipe_id,
	COALESCE(MIN(rpr.need_fulfilled), 1) AS need_fulfilled,
	COALESCE(MIN(rpr.need_fulfilled_with_shopping_list), 1) AS need_fulfilled_with_shopping_list,
	COALESCE(rmpc.missing_products_count, 0) AS missing_products_count,
	COALESCE(SUM(rpr.costs), 0) AS costs,
	COALESCE(SUM(rpr.costs) / CASE WHEN COALESCE(r.desired_servings, 0) = 0 THEN 1 ELSE r.desired_servings END, 0) AS costs_per_serving,
	COALESCE(SUM(rpr.calories), 0) AS calories,
	COALESCE(SUM(rpr.due_score), 0) AS due_score,
	GROUP_CONCAT(rpr.product_name) AS product_names_comma_separated,
	CASE WHEN MIN(COALESCE(rpr.costs, 0)) = 0 THEN 1 ELSE 0 END AS prices_incomplete
FROM recipes r
LEFT JOIN recipes_pos_resolved rpr
	ON r.id = rpr.recipe_id
LEFT JOIN recipes_missing_product_counts rmpc
	ON r.id = rmpc.recipe_id
GROUP BY r.id;;
