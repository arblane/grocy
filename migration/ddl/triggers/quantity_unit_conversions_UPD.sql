-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER quantity_unit_conversions_UPD AFTER UPDATE ON quantity_unit_conversions FOR EACH ROW
BEGIN
-- Update the inverse QU conversion
	UPDATE quantity_unit_conversions
	SET factor = 1 / IFNULL(NEW.factor, 1),
	from_qu_id = NEW.to_qu_id,
	to_qu_id = NEW.from_qu_id
	WHERE from_qu_id = OLD.to_qu_id
		AND to_qu_id = OLD.from_qu_id
		AND IFNULL(product_id, -1) = IFNULL(NEW.product_id, -1);

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
