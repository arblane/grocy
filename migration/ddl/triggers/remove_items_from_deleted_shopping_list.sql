-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER remove_items_from_deleted_shopping_list AFTER DELETE ON shopping_lists FOR EACH ROW
BEGIN
DELETE FROM shopping_list WHERE shopping_list_id = OLD.id;
END;
$$
DELIMITER ;
