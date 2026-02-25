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
