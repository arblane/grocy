DELIMITER //
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
END//
DELIMITER ;
