-- Refine notes: Rewrote 1 '||' concatenation(s) into CONCAT()
-- Converted view (MariaDB-compatible)

-- Flags: CONCAT(', ') -> CONCAT() (best-effort)
CREATE OR REPLACE VIEW product_barcodes_view AS
SELECT
	pb.id,
	pb.product_id,
	pb.barcode,
	pb.qu_id,
	pb.amount,
	pb.shopping_location_id,
	pb.last_price,
	pb.note
FROM product_barcodes pb

UNION ALL

-- Product Grocycodes
SELECT
	p.id,
	p.id AS product_id,
	CONCAT('grcy:p:', CAST(p.id AS CHAR)) AS barcode,
	p.qu_id_stock AS qu_id,
	NULL AS amount,
	NULL AS shopping_location_id,
	NULL AS last_price,
	NULL AS note
FROM products p
/* product_barcodes_view(id,product_id,barcode,qu_id,amount,shopping_location_id,last_price,note) */;;
