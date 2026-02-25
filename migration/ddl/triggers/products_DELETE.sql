-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER products_DELETE AFTER DELETE ON products FOR EACH ROW
BEGIN
-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = OLD.id;
END;
$$
DELIMITER ;
