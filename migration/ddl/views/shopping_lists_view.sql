-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW shopping_lists_view AS
SELECT
	*,
	(SELECT COALESCE(COUNT(*), 0) FROM shopping_list WHERE shopping_list_id = sl.id) AS item_count
FROM shopping_lists sl
/* shopping_lists_view(id,name,description,row_created_timestamp,item_count) */;;
