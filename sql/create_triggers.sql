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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
-- UNPARSED TRIGGER cascade_change_qu_id_stock2
-- Original:
-- CREATE TRIGGER cascade_change_qu_id_stock2 AFTER UPDATE ON products WHEN NEW.qu_id_stock != OLD.qu_id_stock
-- BEGIN
-- 	-- See also the trigger "cascade_change_qu_id_stock BEFORE UPDATE ON products"
-- 	-- This here applies the needed changes to the products table itself only AFTER the update
-- 
-- 	UPDATE products
-- 	SET quick_consume_amount = quick_consume_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
-- 	quick_open_amount = quick_open_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
-- 	calories = calories / IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
-- 	tare_weight = tare_weight * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
-- 	WHERE id = NEW.id;
-- END;
-- 
-- 

$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
-- UNPARSED TRIGGER cascade_change_qu_id_stock
-- Original:
-- CREATE TRIGGER cascade_change_qu_id_stock BEFORE UPDATE ON products WHEN NEW.qu_id_stock != OLD.qu_id_stock
-- BEGIN
-- 	-- All amounts anywhere are related to the products stock QU,
-- 	-- so apply the appropriate unit conversion to all amounts everywhere on change
-- 	-- (and enforce that such a conversion need to exist when the product was once added to stock)
-- 
-- 	SELECT CASE WHEN((
-- 		SELECT 1
-- 		FROM quantity_unit_conversions_resolved
-- 		WHERE product_id = NEW.id
-- 			AND from_qu_id = OLD.qu_id_stock
-- 			AND to_qu_id = NEW.qu_id_stock
-- 	) IS NULL)
-- 	AND
-- 	((
--         SELECT 1
--         FROM stock_log
-- 		WHERE product_id = NEW.id
-- 			AND NEW.qu_id_stock != OLD.qu_id_stock
--     ) IS NOT NULL) THEN RAISE(ABORT, "qu_id_stock can only be changed when a corresponding QU conversion (old QU => new QU) exists when the product was once added to stock") END;
-- 
-- 

$$
DELIMITER ;
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER cascade_product_removal AFTER DELETE ON products FOR EACH ROW
BEGIN
DELETE FROM stock
	WHERE product_id = OLD.id;

	DELETE FROM stock_log
	WHERE product_id = OLD.id;

	DELETE FROM product_barcodes
	WHERE product_id = OLD.id;

	DELETE FROM quantity_unit_conversions
	WHERE product_id = OLD.id;

	DELETE FROM recipes_pos
	WHERE product_id = OLD.id;

	UPDATE recipes
	SET product_id = NULL
	WHERE product_id = OLD.id;

	DELETE FROM meal_plan
	WHERE product_id = OLD.id
		AND `type` = 'product';

	DELETE FROM shopping_list
	WHERE product_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'products');
END;
$$
DELIMITER ;
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER create_internal_recipe AFTER INSERT ON meal_plan FOR EACH ROW
BEGIN
/* This contains practically the same logic as the trigger remove_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = NEW.day
		AND `type` = 'mealplan-day';

	REPLACE INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), NEW.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v'))
		AND `type` = 'mealplan-week';

	INSERT INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = NEW.day
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week'), recipe_id, SUM(recipe_servings)

	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(NEW.day, '%Y-%v')
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = NEW.day
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(NEW.day, '%Y-%v')
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Create a shadow recipe per meal plan recipe
	INSERT INTO recipes
		(id, name, `type`)
	SELECT (SELECT MIN(id) - 1 FROM recipes), CONCAT(CAST(NEW.day AS CHAR), '#', CAST(id AS CHAR)), 'mealplan-shadow'
	FROM meal_plan
	WHERE id = NEW.id
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL;

	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = CONCAT(CAST(NEW.day AS CHAR), '#', CAST(meal_plan.id AS CHAR)) AND `type` = 'mealplan-shadow'), recipe_id, recipe_servings
	FROM meal_plan
	WHERE id = NEW.id
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL;

	-- Enforce "when empty then null" for certain columns
	UPDATE meal_plan
	SET recipe_id = NULL
	WHERE id = NEW.id
		AND IFNULL(recipe_id, '') = '';

	UPDATE meal_plan
	SET product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_id, '') = '';

	UPDATE meal_plan
	SET product_qu_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_qu_id, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_qu_id_consume AFTER INSERT ON products FOR EACH ROW
BEGIN
UPDATE products
	SET qu_id_consume = qu_id_stock
	WHERE id = NEW.id
		AND IFNULL(qu_id_consume, 0) = 0;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_qu_INS AFTER INSERT ON product_barcodes FOR EACH ROW
BEGIN
UPDATE product_barcodes
	SET qu_id = (SELECT qu_id_stock FROM products WHERE id = product_barcodes.product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, 0) = 0;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_qu_UPD AFTER UPDATE ON product_barcodes FOR EACH ROW
BEGIN
UPDATE product_barcodes
	SET qu_id = (SELECT qu_id_stock FROM products WHERE id = product_barcodes.product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, 0) = 0;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_start_date_when_empty_INS AFTER INSERT ON chores FOR EACH ROW
BEGIN
UPDATE chores
	SET start_date =  NOW()
	WHERE id = NEW.id
		AND IFNULL(start_date, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER default_start_date_when_empty_UPD AFTER UPDATE ON chores FOR EACH ROW
BEGIN
UPDATE chores
	SET start_date =  NOW()
	WHERE id = NEW.id
		AND IFNULL(start_date, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enforce_min_stock_amount_for_cumulated_childs_INS AFTER INSERT ON products FOR EACH ROW
BEGIN
/*
		When a parent product has cumulate_min_stock_amount_of_sub_products enabled,
		the child should not have any min_stock_amount
	*/

	UPDATE products
	SET min_stock_amount = 0
	WHERE id IN (
			SELECT
				p_child.id
			FROM products p_parent
			JOIN products p_child
				ON p_child.parent_product_id = p_parent.id
			WHERE p_parent.id = NEW.id
				AND IFNULL(p_parent.cumulate_min_stock_amount_of_sub_products, 0) = 1
			)
		AND min_stock_amount > 0;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enforce_min_stock_amount_for_cumulated_childs_UPD AFTER UPDATE ON products FOR EACH ROW
BEGIN
/*
		When a parent product has cumulate_min_stock_amount_of_sub_products enabled,
		the child should not have any min_stock_amount
	*/

	UPDATE products
	SET min_stock_amount = 0
	WHERE id IN (
			SELECT
				p_child.id
			FROM products p_parent
			JOIN products p_child
				ON p_child.parent_product_id = p_parent.id
			WHERE p_parent.id = NEW.id
				AND IFNULL(p_parent.cumulate_min_stock_amount_of_sub_products, 0) = 1
			)
		AND min_stock_amount > 0;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enforce_parent_product_id_null_when_empty_INS AFTER INSERT ON products FOR EACH ROW
BEGIN
UPDATE products
	SET parent_product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(parent_product_id, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enforce_parent_product_id_null_when_empty_UPD AFTER UPDATE ON products FOR EACH ROW
BEGIN
UPDATE products
	SET parent_product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(parent_product_id, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER enfore_product_nesting_level BEFORE UPDATE ON products FOR EACH ROW
BEGIN
-- Currently only 1 level is supported
	IF EXISTS(
		SELECT 1
		FROM products p
		WHERE IFNULL(NEW.parent_product_id, '') != ''
			AND IFNULL(parent_product_id, '') = NEW.id
	) THEN
		SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT='Unsupported product nesting level detected (currently only 1 level is supported)';
	END IF;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_adding_barcodes_for_not_existing_products AFTER INSERT ON product_barcodes FOR EACH ROW
BEGIN
IF NOT EXISTS(
		SELECT 1
		FROM products p
		WHERE id = NEW.product_id
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='product_id doesn''t reference a existing product';
END IF;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_adding_no_own_stock_products_to_stock AFTER INSERT ON stock FOR EACH ROW
BEGIN
IF EXISTS(
		SELECT 1
		FROM products p
		WHERE id = NEW.product_id
			AND no_own_stock = 1
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='no_own_stock=1 products can''t be added to stock';
END IF;
END;
$$
DELIMITER ;
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_empty_userfields_UPD AFTER UPDATE ON userfield_values FOR EACH ROW
BEGIN
DELETE FROM userfield_values
	WHERE id = NEW.id
		AND IFNULL(value, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_infinite_nested_recipes_INS BEFORE INSERT ON recipes_nestings FOR EACH ROW
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_internal_meal_plan_section_removal BEFORE DELETE ON meal_plan_sections FOR EACH ROW
BEGIN
IF EXISTS(
		SELECT 1
		FROM meal_plan_sections
		WHERE id = OLD.id
			AND id = -1
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='This is an internally used/required default section and therefore can''t be deleted';
END IF;
END;
$$
DELIMITER ;
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER prevent_self_nested_recipes_UPD BEFORE UPDATE ON recipes_nestings FOR EACH ROW
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER products_default_qu_conversions AFTER INSERT ON products FOR EACH ROW
BEGIN
-- Create product specific 1:1 conversions when QU stock != QU purchase/consume/price
	-- and when no default QU conversion apply

	-- with qu_id_stock != qu_id_purchase
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_purchase, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_purchase
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_purchase);

	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_stock, p.qu_id_purchase, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_purchase
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_purchase);

	-- with qu_id_stock != qu_id_consume
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_consume, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_consume
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_consume);

	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_stock, p.qu_id_consume, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_consume
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_consume);

	-- with qu_id_stock != qu_id_price
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_price, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_price
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_price);

	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_stock, p.qu_id_price, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_price
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_price);
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER products_DELETE AFTER DELETE ON products FOR EACH ROW
BEGIN
-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = OLD.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER products_INS AFTER INSERT ON products FOR EACH ROW
BEGIN
-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER products_UPD AFTER UPDATE ON products FOR EACH ROW
BEGIN
-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER quantity_unit_conversions_DEL AFTER DELETE ON quantity_unit_conversions FOR EACH ROW
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', OLD.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.from_qu_id, '/%');

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', OLD.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.from_qu_id, '/%');
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER quantity_unit_conversions_INS AFTER INSERT ON quantity_unit_conversions FOR EACH ROW
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', NEW.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', NEW.from_qu_id, '/%');

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', NEW.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', NEW.from_qu_id, '/%');
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER quantity_unit_conversions_UPD AFTER UPDATE ON quantity_unit_conversions FOR EACH ROW
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', NEW.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', NEW.from_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.from_qu_id, '/%');

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE CONCAT('%/', NEW.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', NEW.from_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.to_qu_id, '/%')
		OR path LIKE CONCAT('%/', OLD.from_qu_id, '/%');
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER qu_conversions_custom_constraint_INS BEFORE INSERT ON quantity_unit_conversions FOR EACH ROW
BEGIN
/*
		Necessary because unique constraints do not include NULL values in SQLite
	*/
IF EXISTS(
	SELECT 1
	FROM quantity_unit_conversions
	WHERE from_qu_id = NEW.from_qu_id
		AND to_qu_id = NEW.to_qu_id
		AND IFNULL(product_id, 0) = IFNULL(NEW.product_id, 0)
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='QU conversion already exists';
END IF;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER qu_conversions_custom_constraint_UPD BEFORE UPDATE ON quantity_unit_conversions FOR EACH ROW
BEGIN
/* This contains practically the same logic as the trigger qu_conversions_custom_constraint_INS */

	/*
		Necessary because unique constraints do not include NULL values in SQLite
		*/
IF EXISTS(
	SELECT 1
	FROM quantity_unit_conversions
	WHERE from_qu_id = NEW.from_qu_id
		AND to_qu_id = NEW.to_qu_id
		AND IFNULL(product_id, 0) = IFNULL(NEW.product_id, 0)
		AND id != NEW.id
	) THEN
	SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT='QU conversion already exists';
END IF;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER recipes_desired_servings_default AFTER INSERT ON recipes FOR EACH ROW
BEGIN
UPDATE recipes
	SET desired_servings = base_servings
	WHERE id = NEW.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER recipes_pos_qu_id_default AFTER INSERT ON recipes_pos FOR EACH ROW
BEGIN
UPDATE recipes_pos
	SET qu_id = (SELECT qu_id_stock FROM products where id = product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, '') = '';

	IF NOT EXISTS(
		SELECT 1 FROM (
			SELECT 1
			FROM recipes_pos rp
			JOIN quantity_unit_conversions_resolved qucr
				ON qucr.product_id = rp.product_id
				AND qucr.to_qu_id = rp.qu_id
			WHERE rp.id = NEW.id

			UNION

			-- only_check_single_unit_in_stock = 1 ingredients can have any QU
			SELECT 1
			FROM recipes_pos rp
			WHERE rp.id = NEW.id
				AND IFNULL(rp.only_check_single_unit_in_stock, 0) = 1
		) AS qu_exists
	) THEN
		SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT='Provided qu_id doesn''t have a related conversion for that product';
	END IF;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_conversions AFTER DELETE ON quantity_units FOR EACH ROW
BEGIN
DELETE FROM quantity_unit_conversions
	WHERE from_qu_id = OLD.id
		OR to_qu_id = OLD.id;
END;
$$
DELIMITER ;
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
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_items_from_deleted_shopping_list AFTER DELETE ON shopping_lists FOR EACH ROW
BEGIN
DELETE FROM shopping_list WHERE shopping_list_id = OLD.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_recipe_from_meal_plans AFTER DELETE ON recipes FOR EACH ROW
BEGIN
DELETE FROM meal_plan
	WHERE recipe_id = OLD.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER set_products_default_location_if_empty_stock_log AFTER INSERT ON stock_log FOR EACH ROW
BEGIN
UPDATE stock_log
	SET location_id = (SELECT location_id FROM products where id = product_id)
	WHERE id = NEW.id
		AND location_id IS NULL;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER set_products_default_location_if_empty_stock AFTER INSERT ON stock FOR EACH ROW
BEGIN
UPDATE stock
	SET location_id = (SELECT location_id FROM products where id = product_id)
	WHERE id = NEW.id
		AND location_id IS NULL;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER shopping_list_defaults_INS AFTER INSERT ON shopping_list FOR EACH ROW
BEGIN
UPDATE shopping_list
	SET qu_id = (SELECT qu_id_purchase FROM products WHERE id = product_id)
	WHERE IFNULL(qu_id, '') = ''
		AND id = NEW.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER shopping_list_defaults_UPD AFTER UPDATE ON shopping_list FOR EACH ROW
BEGIN
UPDATE shopping_list
	SET qu_id = (SELECT qu_id_purchase FROM products WHERE id = product_id)
	WHERE IFNULL(qu_id, '') = ''
		AND id = NEW.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_log_DEL AFTER DELETE ON stock_log FOR EACH ROW
BEGIN
-- Update products_average_price cache
	DELETE FROM cache__products_average_price
	WHERE product_id = OLD.id;

	-- Update products_last_purchased cache
	DELETE FROM cache__products_last_purchased
	WHERE product_id = OLD.id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_log_INS AFTER INSERT ON stock_log FOR EACH ROW
BEGIN
-- Update products_average_price cache
	REPLACE INTO cache__products_average_price
		(product_id, price)
	SELECT product_id, price
	FROM products_average_price
	WHERE product_id = NEW.product_id;

	-- Update products_last_purchased cache
	REPLACE INTO cache__products_last_purchased
		(product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
	SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
	FROM products_last_purchased
	WHERE product_id = NEW.product_id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_log_UPD AFTER UPDATE ON stock_log FOR EACH ROW
BEGIN
-- Update products_average_price cache
	REPLACE INTO cache__products_average_price
		(product_id, price)
	SELECT product_id, price
	FROM products_average_price
	WHERE product_id = NEW.product_id;

	-- Update products_last_purchased cache
	REPLACE INTO cache__products_last_purchased
		(product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
	SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
	FROM products_last_purchased
	WHERE product_id = NEW.product_id;
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER stock_missing_products AFTER INSERT ON stock FOR EACH ROW
BEGIN
-- placeholder if needed
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
-- UNPARSED TRIGGER stock_next_use_DEL
-- Original:
-- CREATE TRIGGER stock_next_use_DEL INSTEAD OF DELETE ON stock_next_use
-- BEGIN
-- 	DELETE FROM stock
-- 	WHERE id = OLD.id;
-- END;
-- 
-- 

$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
-- UNPARSED TRIGGER stock_next_use_INS
-- Original:
-- CREATE TRIGGER stock_next_use_INS INSTEAD OF INSERT ON stock_next_use
-- BEGIN
-- 	INSERT INTO stock
-- 		(product_id, amount, best_before_date, purchased_date, stock_id,
-- 		price, open, opened_date, location_id, shopping_location_id, note)
-- 	VALUES
-- 		(NEW.product_id, NEW.amount, NEW.best_before_date, NEW.purchased_date, NEW.stock_id,
-- 		NEW.price, NEW.open, NEW.opened_date, NEW.location_id, NEW.shopping_location_id, NEW.note);
-- END;
-- 
-- 

$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
-- UNPARSED TRIGGER stock_next_use_UPD
-- Original:
-- CREATE TRIGGER stock_next_use_UPD INSTEAD OF UPDATE ON stock_next_use
-- BEGIN
-- 	UPDATE stock
-- 	SET product_id = NEW.product_id,
-- 	amount = NEW.amount,
-- 	best_before_date = NEW.best_before_date,
-- 	purchased_date = NEW.purchased_date,
-- 	stock_id = NEW.stock_id,
-- 	price = NEW.price,
-- 	open = NEW.open,
-- 	opened_date = NEW.opened_date,
-- 	location_id = NEW.location_id,
-- 	shopping_location_id = NEW.shopping_location_id,
-- 	note = NEW.note
-- 	WHERE id = NEW.id;
-- END;
-- 
-- 

$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER update_internal_recipe AFTER UPDATE ON meal_plan FOR EACH ROW
BEGIN
/* This contains practically the same logic as the trigger create_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = NEW.day
		AND `type` = 'mealplan-day';

	REPLACE INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), NEW.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v'))
		AND `type` = 'mealplan-week';

	INSERT INTO recipes
		(id, name, `type`)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = NEW.day
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(NEW.day, '%Y-%v')
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND `type` = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = NEW.day
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = TRIM(LEADING '0' FROM DATE_FORMAT(NEW.day, '%Y-%v')) AND `type` = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE DATE_FORMAT(day, '%Y-%v') = DATE_FORMAT(NEW.day, '%Y-%v')
		AND `type` = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Create a shadow recipe per meal plan recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (
		SELECT id FROM recipes
		WHERE name IN (
			SELECT CONCAT(CAST(NEW.day AS CHAR), '#', CAST(NEW.id AS CHAR))
			FROM meal_plan
			WHERE day = NEW.day
		)
		AND `type` = 'mealplan-shadow'
	);

	DELETE FROM recipes
	WHERE `type` = 'mealplan-shadow'
		AND name = CONCAT(CAST(NEW.day AS CHAR), '#', CAST(NEW.id AS CHAR));

	INSERT INTO recipes
		(id, name, `type`)
	SELECT (SELECT MIN(id) - 1 FROM recipes), CONCAT(CAST(NEW.day AS CHAR), '#', CAST(id AS CHAR)), 'mealplan-shadow'
	FROM meal_plan
	WHERE id = NEW.id
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL;

	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = CONCAT(CAST(NEW.day AS CHAR), '#', CAST(meal_plan.id AS CHAR)) AND `type` = 'mealplan-shadow'), recipe_id, recipe_servings
	FROM meal_plan
	WHERE id = NEW.id
		AND `type` = 'recipe'
		AND recipe_id IS NOT NULL;

	-- Enforce "when empty then null" for certain columns
	UPDATE meal_plan
	SET recipe_id = NULL
	WHERE id = NEW.id
		AND IFNULL(recipe_id, '') = '';

	UPDATE meal_plan
	SET product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_id, '') = '';

	UPDATE meal_plan
	SET product_qu_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_qu_id, '') = '';
END;
$$
DELIMITER ;
-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER userfield_values_special_handling_INS AFTER INSERT ON userfield_values FOR EACH ROW
BEGIN
-- Entity stock:
	-- object_id is the transaction_id on insert -> replace it by the corresponding stock_id
	REPLACE INTO userfield_values
		(field_id, object_id, value)
	SELECT uv.field_id, sl.stock_id, uv.value
	FROM userfield_values uv
	JOIN stock_log sl
		ON uv.object_id = sl.transaction_id
		AND sl.transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')
	WHERE uv.field_id IN (SELECT id FROM userfields WHERE entity = 'stock')
		AND uv.field_id = NEW.field_id
		AND uv.object_id = NEW.object_id;

	DELETE FROM userfield_values
	WHERE field_id IN (SELECT id FROM userfields WHERE entity = 'stock')
		AND field_id = NEW.field_id
		AND object_id = NEW.object_id;
END;
$$
DELIMITER ;
