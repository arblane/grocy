-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_log_DEL AFTER DELETE ON stock_log FOR EACH ROW
BEGIN
-- Update products_average_price cache
	DELETE FROM cache__products_average_price
	WHERE product_id = OLD.id;

	-- Update products_last_purchased cache
	DELETE FROM cache__products_last_purchased
	WHERE product_id = OLD.id;
END;
$$
DELIMITER ;
