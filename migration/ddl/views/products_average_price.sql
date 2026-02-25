-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
-- CRITICAL: Use SQL SECURITY INVOKER to prevent permission issues when defined by root@%
CREATE DEFINER=`root`@`%` SQL SECURITY INVOKER VIEW products_average_price AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	sl.product_id,
	SUM(COALESCE(sl.edited_origin_amount, sl.amount) * sl.price) / SUM(COALESCE(sl.edited_origin_amount, sl.amount)) as price
FROM (
	SELECT sl.*, CASE WHEN sl.transaction_type = 'stock-edit-new' THEN see.edited_origin_amount END AS edited_origin_amount
	FROM stock_log sl
	LEFT JOIN stock_edited_entries see
		ON sl.stock_id = see.stock_id
) sl
WHERE sl.undone = 0
	AND (
		(sl.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries)) -- Unedited origin entries
		OR (sl.transaction_type = 'stock-edit-new' AND sl.id IN (SELECT stock_log_id_of_newest_edited_entry FROM stock_edited_entries)) -- Edited origin entries => take the newest "stock-edit-new" one
	)
	AND COALESCE(sl.price, 0) > 0
	AND COALESCE(sl.amount, 0) > 0
GROUP BY sl.product_id
/* products_average_price(id,product_id,price) */;;
