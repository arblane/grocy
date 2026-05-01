-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER userfield_values_special_handling_INS AFTER INSERT ON userfield_values FOR EACH ROW
BEGIN
	-- Only execute for stock entity userfields; skip for all other entities to avoid
	-- MariaDB error 1442 (can't update table 'userfield_values' used by triggering statement)
	IF NEW.field_id IN (SELECT id FROM userfields WHERE entity = 'stock') THEN
		-- Entity stock:
		-- object_id is the transaction_id on insert -> replace it by the corresponding stock_id
		REPLACE INTO userfield_values
			(field_id, object_id, value)
		SELECT uv.field_id, sl.stock_id, uv.value
		FROM userfield_values uv
		JOIN stock_log sl
			ON uv.object_id = sl.transaction_id
			AND sl.transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')
		WHERE uv.field_id = NEW.field_id
			AND uv.object_id = NEW.object_id;

		DELETE FROM userfield_values
		WHERE field_id = NEW.field_id
			AND object_id = NEW.object_id
			AND field_id IN (SELECT id FROM userfields WHERE entity = 'stock');
	END IF;
END;
$$
DELIMITER ;
