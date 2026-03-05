-- Converted trigger (MariaDB compatible)
-- NOTE: Cache refresh queries against products_average_price/products_last_purchased
-- inside stock_log triggers fail in MariaDB (ERROR 1356) because these views
-- reference stock_log. Price caches are refreshed outside trigger context.

DELIMITER $$
CREATE TRIGGER stock_log_INS AFTER INSERT ON stock_log FOR EACH ROW
BEGIN
	DO 0;
END;
$$
DELIMITER ;
