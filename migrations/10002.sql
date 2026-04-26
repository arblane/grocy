DROP VIEW uihelper_shopping_list;
CREATE VIEW uihelper_shopping_list
AS
SELECT
	sl.*,
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
	plp.price * IFNULL(quc.factor, 1.0) AS last_price_unit,
	plp.price * sl.amount AS last_price_total,
	plp.price AS price,
	st.name AS default_shopping_location_name,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	pg.id AS product_group_id,
	pg.name AS product_group_name,
	pbcs.barcodes AS product_barcodes
FROM shopping_list sl
LEFT JOIN products p
	ON sl.product_id = p.id
LEFT JOIN cache__products_last_purchased plp
	ON sl.product_id = plp.product_id
LEFT JOIN shopping_locations st
	ON p.shopping_location_id = st.id
LEFT JOIN quantity_units qu
	ON sl.qu_id = qu.id
LEFT JOIN product_groups pg
	ON p.product_group_id = pg.id
LEFT JOIN cache__quantity_unit_conversions_resolved quc
	ON p.id = quc.product_id
	AND p.qu_id_stock = quc.to_qu_id
	AND sl.qu_id = quc.from_qu_id
LEFT JOIN product_barcodes_comma_separated pbcs
	ON sl.product_id = pbcs.product_id;

DROP VIEW uihelper_stock_journal;
CREATE VIEW uihelper_stock_journal
AS
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
	ON p.qu_id_stock = qu.id;

DROP VIEW uihelper_stock_journal_summary;
CREATE VIEW uihelper_stock_journal_summary
AS
SELECT
	user_id AS id,
	user_id,
	u.display_name AS user_display_name,
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
	ON sl.user_id = u.id
JOIN products p
	ON sl.product_id = p.id
JOIN quantity_units qu
	ON p.qu_id_stock = qu.id
WHERE undone = 0
GROUP BY user_id, product_id, transaction_type;