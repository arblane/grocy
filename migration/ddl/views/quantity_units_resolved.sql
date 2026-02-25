-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW quantity_units_resolved AS
-- This view builds the relationship between QUs based on their (default) conversions

SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	qu.id AS qu_id,
	quc.to_qu_id AS related_qu_id,
	quc.factor
FROM quantity_units qu
JOIN quantity_unit_conversions quc
	ON qu.id = quc.from_qu_id
	AND quc.product_id IS NULL
/* quantity_units_resolved(id,qu_id,related_qu_id,factor) */;;
