-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_adding_no_own_stock_products_to_stock AFTER INSERT ON stock FOR EACH ROW
BEGIN
IF EXISTS(
		SELECT 1
		FROM products p
		WHERE id = NEW.product_id
			AND no_own_stock = 1
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='no_own_stock=1 products can''t be added to stock';
END IF;
END;
$$
DELIMITER ;
