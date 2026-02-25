-- Converted trigger (MariaDB compatible)

DELIMITER $$
CREATE TRIGGER quantity_unit_conversions_INS AFTER INSERT ON quantity_unit_conversions FOR EACH ROW
BEGIN
-- Create the inverse QU conversion
	REPLACE INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	VALUES
		(NEW.to_qu_id, NEW.from_qu_id, 1 / IFNULL(NEW.factor, 1), NEW.product_id);

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
