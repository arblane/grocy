-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_recipe_from_meal_plans AFTER DELETE ON recipes FOR EACH ROW
BEGIN
DELETE FROM meal_plan
	WHERE recipe_id = OLD.id
		AND IFNULL(OLD.type, '') NOT IN ('mealplan-day', 'mealplan-week', 'mealplan-shadow');
END;
$$
DELIMITER ;
