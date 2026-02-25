-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER shopping_list_defaults_UPD BEFORE UPDATE ON shopping_list FOR EACH ROW
BEGIN
	IF IFNULL(NEW.qu_id, '') = '' THEN
		SET NEW.qu_id = (SELECT qu_id_purchase FROM products WHERE id = NEW.product_id);
	END IF;
END;
$$
DELIMITER ;
