-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW stock_average_product_shelf_life AS
SELECT
	p.id,
	CASE WHEN x.product_id IS NULL THEN -1 ELSE AVG(x.shelf_life_days) END AS average_shelf_life_days
FROM products p
LEFT JOIN (
		SELECT
			sl_p.product_id,
			DATEDIFF(sl_p.best_before_date, sl_p.purchased_date) AS shelf_life_days
		FROM stock_log sl_p
		WHERE sl_p.undone = 0
			AND (
				(sl_p.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl_p.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries))
				OR (sl_p.transaction_type = 'stock-edit-new' AND sl_p.stock_id IN (SELECT stock_id FROM stock_edited_entries))
			)
	) x
	ON p.id = x.product_id
GROUP BY p.id
/* stock_average_product_shelf_life(id,average_shelf_life_days) */;;
