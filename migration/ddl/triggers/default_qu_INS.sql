-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_qu_INS BEFORE INSERT ON product_barcodes FOR EACH ROW
BEGIN
	IF IFNULL(NEW.qu_id, 0) = 0 THEN
		SET NEW.qu_id = (SELECT qu_id_stock FROM products WHERE id = NEW.product_id);
	END IF;
END;
$$
DELIMITER ;
