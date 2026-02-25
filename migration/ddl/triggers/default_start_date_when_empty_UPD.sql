-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_start_date_when_empty_UPD BEFORE UPDATE ON chores FOR EACH ROW
BEGIN
	IF IFNULL(NEW.start_date, '') = '' THEN
		SET NEW.start_date = NOW();
	END IF;
END;
$$
DELIMITER ;
