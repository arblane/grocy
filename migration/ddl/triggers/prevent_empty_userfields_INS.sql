-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_empty_userfields_INS AFTER INSERT ON userfield_values FOR EACH ROW
BEGIN
DELETE FROM userfield_values
	WHERE id = NEW.id
		AND IFNULL(value, '') = '';
END;
$$
DELIMITER ;
