-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW stock_current_location_content AS
SELECT
	COALESCE(s.location_id, p.location_id) AS location_id,
	s.product_id,
	SUM(s.amount) AS amount,
	ROUND(SUM(COALESCE(s.price, 0) * s.amount), 2) AS value,
	MIN(s.best_before_date) AS best_before_date,
	COALESCE((SELECT SUM(amount) FROM stock WHERE product_id = s.product_id AND location_id = s.location_id AND open = 1), 0) AS amount_opened
FROM stock s
JOIN products p
	ON s.product_id = p.id
	AND p.active = 1
GROUP BY COALESCE(s.location_id, p.location_id), s.product_id
/* stock_current_location_content(location_id,product_id,amount,value,best_before_date,amount_opened) */;;
