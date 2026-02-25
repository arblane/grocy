-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_log_INS AFTER INSERT ON stock_log FOR EACH ROW
BEGIN
-- Update products_average_price cache
	REPLACE INTO cache__products_average_price
		(product_id, price)
	SELECT product_id, price
	FROM products_average_price
	WHERE product_id = NEW.product_id;

	-- Update products_last_purchased cache
	REPLACE INTO cache__products_last_purchased
		(product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
	SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
	FROM products_last_purchased
	WHERE product_id = NEW.product_id;
END;
$$
DELIMITER ;
