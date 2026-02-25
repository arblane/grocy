-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW products_current_substitutions AS
/*
	When a parent product is not in stock itself,
	any sub product (the next based on the default consume rule) should be used

	This view lists all parent products and in the column `product_id_effective` either itself,
	when the corresponding parent product is currently in stock itself, or otherwise the next sub product to use
*/

SELECT
	-1, -- Dummy
	p_sub.id AS parent_product_id,
	CASE WHEN p_sub.has_sub_products = 1 THEN
		CASE WHEN COALESCE(sc.amount, 0) = 0 THEN -- Parent product itself is currently not in stock => use the next sub product
			(
			SELECT x_snu.product_id
			FROM products_resolved x_pr
			JOIN stock_next_use x_snu
				ON x_pr.sub_product_id = x_snu.product_id
			WHERE x_pr.parent_product_id = p_sub.id
				AND x_pr.parent_product_id != x_pr.sub_product_id
			ORDER BY x_snu.priority DESC, x_snu.open DESC, x_snu.best_before_date ASC, x_snu.purchased_date ASC
			LIMIT 1
			)
		ELSE -- Parent product itself is currently in stock => use it
			p_sub.id
		END
	END AS product_id_effective
FROM products_view p
JOIN products_resolved pr
	ON p.id = pr.parent_product_id
JOIN products_view p_sub
	ON pr.sub_product_id = p_sub.id
JOIN stock_current sc
	ON p_sub.id = sc.product_id
WHERE p_sub.has_sub_products = 1
/* products_current_substitutions("-1",parent_product_id,product_id_effective) */;;
