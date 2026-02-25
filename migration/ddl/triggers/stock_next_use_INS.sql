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
