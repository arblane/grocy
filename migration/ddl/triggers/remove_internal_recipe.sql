-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_internal_recipe AFTER DELETE ON meal_plan FOR EACH ROW
BEGIN
/* This contains practically the same logic as the trigger create_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = OLD.day
		AND `type` = 'mealplan-day';

	REPLACE INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), OLD.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(OLD.day, '%Y-%v'))
		AND `type` = 'mealplan-week';

	INSERT INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), TRIM(LEADING '0' FROM DATE_FORMAT(OLD.day, '%Y-%v')), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = OLD.day AND `type` = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(OLD.day, '%Y-%v')) AND `type` = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = OLD.day AND `type` = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = OLD.day
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(OLD.day, '%Y-%v')) AND `type` = 'mealplan-week'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(OLD.day, '%Y-%v')
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = OLD.day AND `type` = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = OLD.day
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(OLD.day, '%Y-%v')) AND `type` = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(OLD.day, '%Y-%v')
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Remove shadow recipes per meal plan recipe
	DELETE FROM recipes
	WHERE `type` = 'mealplan-shadow'
		AND name NOT IN (
			SELECT CONCAT(CAST(day AS CHAR), '#', CAST(id AS CHAR))
			FROM meal_plan
			WHERE `type` = 'recipe'
		);
END;
$$
DELIMITER ;
