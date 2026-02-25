-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER cascade_userfield_removal AFTER DELETE ON userfields FOR EACH ROW
BEGIN
DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id = OLD.id;
END;
$$
DELIMITER ;
