-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_conversions AFTER DELETE ON quantity_units FOR EACH ROW
BEGIN
DELETE FROM quantity_unit_conversions
	WHERE from_qu_id = OLD.id
		OR to_qu_id = OLD.id;
END;
$$
DELIMITER ;
