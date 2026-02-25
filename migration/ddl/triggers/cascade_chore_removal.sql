-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER cascade_chore_removal AFTER DELETE ON chores FOR EACH ROW
BEGIN
DELETE FROM chores_log
	WHERE chore_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'chores');
END;
$$
DELIMITER ;
