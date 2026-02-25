-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER recipes_desired_servings_default BEFORE INSERT ON recipes FOR EACH ROW
BEGIN
	IF NEW.desired_servings IS NULL OR NEW.desired_servings = 0 THEN
		SET NEW.desired_servings = NEW.base_servings;
	END IF;
END;
$$
DELIMITER ;
