-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_self_nested_recipes_INS BEFORE INSERT ON recipes_nestings FOR EACH ROW
BEGIN
IF EXISTS(
	SELECT 1
	FROM recipes_nestings
	WHERE NEW.recipe_id = NEW.includes_recipe_id
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='Recursive nested recipe detected';
END IF;
END;
$$
DELIMITER ;
