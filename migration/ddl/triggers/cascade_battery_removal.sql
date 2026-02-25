-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER cascade_battery_removal AFTER DELETE ON batteries FOR EACH ROW
BEGIN
DELETE FROM battery_charge_cycles
	WHERE battery_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'batteries');
END;
$$
DELIMITER ;
