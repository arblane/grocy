-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW product_qu_relations AS
-- This view builds which product is related to which QU, direct or indirect, based on QU conversions

-- The products stock QU
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	p.qu_id_stock AS qu_id
FROM products p

UNION

-- The products purchase QU
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	p.qu_id_purchase AS qu_id
FROM products p

UNION

-- All (direct) product conversions (product overrides)
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	quc.product_id,
	quc.to_qu_id AS qu_id
FROM quantity_unit_conversions quc
WHERE quc.product_id IS NOT NULL

UNION

-- All (indirect) default QU conversions
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	qur2.qu_id
from products p
JOIN quantity_unit_conversions quc
	ON (p.qu_id_stock = quc.from_qu_id OR p.qu_id_purchase = quc.from_qu_id)
	AND p.id = quc.product_id
JOIN quantity_units_resolved qur1
	ON quc.to_qu_id = qur1.qu_id
JOIN quantity_units_resolved qur2
	ON qur1.related_qu_id = qur2.qu_id
/* product_qu_relations(id,product_id,qu_id) */;;
