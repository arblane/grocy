-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW uihelper_stock_journal_summary AS
SELECT
	user_id AS id, -- Dummy, LessQL needs an id column
	user_id, u.display_name AS user_display_name,
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
	product_id,
	transaction_type,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	SUM(amount) AS amount
FROM stock_log sl
JOIN users_dto u
	on sl.user_id = u.id
JOIN products p
	ON sl.product_id = p.id
JOIN quantity_units qu
	ON p.qu_id_stock = qu.id
WHERE undone = 0
GROUP BY user_id, product_id, transaction_type
/* uihelper_stock_journal_summary(id,user_id,user_display_name,product_name,product_display_name,product_id,transaction_type,qu_name,qu_name_plural,amount) */;;
