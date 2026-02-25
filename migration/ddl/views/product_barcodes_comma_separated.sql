-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW product_barcodes_comma_separated AS
SELECT
	pb.id, -- Dummy, LessQL needs an id column
	pb.product_id,
	GROUP_CONCAT(pb.barcode) AS barcodes
FROM product_barcodes pb
JOIN products p
	ON pb.product_id = p.id
WHERE p.active = 1
GROUP BY pb.product_id
/* product_barcodes_comma_separated(id,product_id,barcodes) */;;
