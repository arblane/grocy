-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_qu_id_consume BEFORE INSERT ON products FOR EACH ROW
BEGIN
	IF IFNULL(NEW.qu_id_consume, 0) = 0 THEN
		SET NEW.qu_id_consume = NEW.qu_id_stock;
	END IF;
END;
$$
DELIMITER ;
