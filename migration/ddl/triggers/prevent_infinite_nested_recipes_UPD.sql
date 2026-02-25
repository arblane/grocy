-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_infinite_nested_recipes_UPD BEFORE UPDATE ON recipes_nestings FOR EACH ROW
BEGIN
IF EXISTS(
    SELECT 1
    FROM recipes_nestings_resolved rnr
    WHERE NEW.recipe_id = rnr.includes_recipe_id
        AND NEW.includes_recipe_id = rnr.recipe_id
    ) THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT='Recursive nested recipe detected';
END IF;
END;
$$
DELIMITER ;
