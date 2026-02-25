-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER set_products_default_location_if_empty_stock BEFORE INSERT ON stock FOR EACH ROW
BEGIN
	IF NEW.location_id IS NULL THEN
		SET NEW.location_id = (SELECT location_id FROM products WHERE id = NEW.product_id);
	END IF;
END;
$$
DELIMITER ;
