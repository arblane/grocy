-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW stock_next_use AS
/*
	The default consume rule is:
	Opened first, then first due first, then first in first out
	Apart from that products at their default consume location should be consumed first

	This orders the stock entries by that
	=> Highest `priority` per product = the stock entry to use next
	=> ORDER BY clause = ORDER BY priority DESC, open DESC, best_before_date ASC, purchased_date ASC
*/

SELECT
	(ROW_NUMBER() OVER(PARTITION BY s.product_id ORDER BY CASE WHEN COALESCE(p.default_consume_location_id, -1) = s.location_id THEN 0 ELSE 1 END ASC, s.open DESC, s.best_before_date ASC, s.purchased_date ASC)) * -1 AS priority,
	s.*
FROM stock s
JOIN products p
	ON p.id = s.product_id
ORDER BY CASE WHEN COALESCE(p.default_consume_location_id, -1) = s.location_id THEN 0 ELSE 1 END ASC, s.open DESC, s.best_before_date ASC, s.purchased_date ASC
/* stock_next_use(priority,id,product_id,amount,best_before_date,purchased_date,stock_id,price,open,opened_date,row_created_timestamp,location_id,shopping_location_id,note) */;;
