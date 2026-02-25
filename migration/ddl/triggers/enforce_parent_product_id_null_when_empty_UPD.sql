-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enforce_parent_product_id_null_when_empty_UPD BEFORE UPDATE ON products FOR EACH ROW
BEGIN
	IF IFNULL(NEW.parent_product_id, '') = '' THEN
		SET NEW.parent_product_id = NULL;
	END IF;
END;
$$
DELIMITER ;
