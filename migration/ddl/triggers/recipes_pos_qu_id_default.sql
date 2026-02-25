-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER recipes_pos_qu_id_default BEFORE INSERT ON recipes_pos FOR EACH ROW
BEGIN
	IF IFNULL(NEW.qu_id, '') = '' THEN
		SET NEW.qu_id = (SELECT qu_id_stock FROM products WHERE id = NEW.product_id);
	END IF;

	IF IFNULL(NEW.only_check_single_unit_in_stock, 0) = 0 THEN
		IF NOT EXISTS(
			SELECT 1
			FROM quantity_unit_conversions_resolved qucr
			WHERE qucr.product_id = NEW.product_id
				AND qucr.to_qu_id = NEW.qu_id
		) THEN
			SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT='Provided qu_id doesn''t have a related conversion for that product';
		END IF;
	END IF;
END;
$$
DELIMITER ;
