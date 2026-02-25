-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW products_view AS
SELECT
	p.*,
	CASE WHEN EXISTS(SELECT 1 FROM products WHERE parent_product_id = p.id) THEN 1 ELSE 0 END AS has_sub_products,
	COALESCE(quc_purchase.factor, 1.0) AS qu_factor_purchase_to_stock,
	COALESCE(quc_consume.factor, 1.0) AS qu_factor_consume_to_stock,
	COALESCE(quc_price.factor, 1.0) AS qu_factor_price_to_stock
FROM products p
LEFT JOIN cache__quantity_unit_conversions_resolved quc_purchase
	ON p.id = quc_purchase.product_id
	AND p.qu_id_purchase = quc_purchase.from_qu_id
	AND p.qu_id_stock = quc_purchase.to_qu_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_consume
	ON p.id = quc_consume.product_id
	AND p.qu_id_consume = quc_consume.from_qu_id
	AND p.qu_id_stock = quc_consume.to_qu_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_price
	ON p.id = quc_price.product_id
	AND p.qu_id_price = quc_price.from_qu_id
	AND p.qu_id_stock = quc_price.to_qu_id
/* products_view(id,name,description,product_group_id,active,location_id,shopping_location_id,qu_id_purchase,qu_id_stock,min_stock_amount,default_best_before_days,default_best_before_days_after_open,default_best_before_days_after_freezing,default_best_before_days_after_thawing,picture_file_name,enable_tare_weight_handling,tare_weight,not_check_stock_fulfillment_for_recipes,parent_product_id,calories,cumulate_min_stock_amount_of_sub_products,due_type,quick_consume_amount,hide_on_stock_overview,default_stock_label_type,should_not_be_frozen,treat_opened_as_out_of_stock,no_own_stock,default_consume_location_id,move_on_open,row_created_timestamp,qu_id_consume,auto_reprint_stock_label,quick_open_amount,qu_id_price,disable_open,default_purchase_price_type,has_sub_products,qu_factor_purchase_to_stock,qu_factor_consume_to_stock,qu_factor_price_to_stock) */;;
