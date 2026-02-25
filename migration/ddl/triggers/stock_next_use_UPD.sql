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
