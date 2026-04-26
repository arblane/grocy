-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW uihelper_stock_journal AS
SELECT
	sl.id,
	sl.row_created_timestamp,
	sl.correlation_id,
	sl.undone,
	sl.undone_timestamp,
	sl.transaction_type,
	sl.spoiled,
	sl.amount,
	sl.location_id,
	l.name AS location_name,
	p.name AS product_name,
	CONCAT(
		CONCAT_WS(', ',
			p.name,
			NULLIF(TRIM(p.additional_details), ''),
			NULLIF(TRIM(p.strength), ''),
			NULLIF(TRIM(p.size), ''),
			NULLIF(TRIM(p.package_configuration), '')
		),
		CASE
			WHEN NULLIF(TRIM(p.brand), '') IS NOT NULL THEN CONCAT(' - ', TRIM(p.brand))
			ELSE ''
		END
	) AS product_display_name,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	u.display_name AS user_display_name,
	p.id AS product_id,
	sl.note,
	sl.stock_id
FROM stock_log sl
LEFT JOIN users_dto u
	ON sl.user_id = u.id
JOIN products p
	ON sl.product_id = p.id
JOIN locations l
	ON sl.location_id = l.id
JOIN quantity_units qu
	ON p.qu_id_stock = qu.id
/* uihelper_stock_journal(id,row_created_timestamp,correlation_id,undone,undone_timestamp,transaction_type,spoiled,amount,location_id,location_name,product_name,product_display_name,qu_name,qu_name_plural,user_display_name,product_id,note,stock_id) */;;
