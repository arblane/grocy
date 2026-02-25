-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE
CREATE OR REPLACE VIEW products_current_price AS
/*
	Current price per product,
	based on the stock entry to use next,
	or on the last price if the product is currently not in stock
*/

SELECT
	-1 AS id, -- Dummy,
	p.id AS product_id,
	COALESCE(snu.price, plp.price) AS price
FROM products p
LEFT JOIN (
	SELECT
		product_id,
		MAX(priority),
		price -- Bare column, ref https://www.sqlite.org/lang_select.html#bare_columns_in_an_aggregate_query
	FROM stock_next_use
	GROUP BY product_id
	ORDER BY priority DESC, open DESC, best_before_date ASC, purchased_date ASC
	) snu
	ON p.id = snu.product_id
LEFT JOIN cache__products_last_purchased plp
	ON p.id = plp.product_id
/* products_current_price(id,product_id,price) */;;
