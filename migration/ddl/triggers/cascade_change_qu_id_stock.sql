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
