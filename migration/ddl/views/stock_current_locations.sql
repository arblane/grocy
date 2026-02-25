-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW stock_current_locations AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	s.product_id,
        SUM(s.amount) as amount,
	s.location_id AS location_id,
	l.name AS location_name,
	l.is_freezer AS location_is_freezer
FROM stock s
JOIN locations l
	ON s.location_id = l.id
GROUP BY s.product_id, s.location_id, l.name
/* stock_current_locations(id,product_id,amount,location_id,location_name,location_is_freezer) */;;
