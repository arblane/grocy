-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW uihelper_shopping_list AS
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
	ON sl.product_id = pbcs.product_id
/* uihelper_shopping_list(id,product_id,note,amount,row_created_timestamp,shopping_list_id,done,qu_id,product_name,product_display_name,last_price_unit,last_price_total,price,default_shopping_location_name,qu_name,qu_name_plural,product_group_id,product_group_name,product_barcodes) */;;
