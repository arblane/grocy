-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW products_volatile_status AS
SELECT
	-1 AS id, -- Dummy
	p.id AS product_id,
	p.name AS product_name,
	CASE WHEN DATEDIFF(sc.best_before_date, NOW()) < 0 THEN
		CASE WHEN p.due_type = 1 THEN 'overdue' ELSE 'expired' END
	ELSE
		CASE WHEN DATEDIFF(sc.best_before_date, NOW()) < CAST(grocy_user_setting('stock_due_soon_days') AS SIGNED) THEN
			'due_soon'
		ELSE
			'ok'
		END
	END AS current_due_status,
	CASE WHEN smp.id IS NOT NULL THEN 1 ELSE 0 END AS is_currently_below_min_stock_amount
FROM products p
LEFT JOIN stock_current sc
	ON p.id = sc.product_id
LEFT JOIN stock_missing_products smp
	ON p.id = smp.id;;
