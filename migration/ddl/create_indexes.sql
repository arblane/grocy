CREATE INDEX ix_recipes ON recipes ( name(191), `type`(191) );

CREATE INDEX ix_stock_performance1 ON stock ( product_id, `open`, best_before_date, amount );

CREATE INDEX ix_chores_performance1 ON chores ( id, active );

CREATE INDEX ix_batteries_performance1 ON batteries ( id, active );

CREATE UNIQUE INDEX ix_product_barcodes ON product_barcodes ( barcode );

CREATE INDEX ix_chores_log_performance1 ON chores_log ( chore_id, undone, tracked_time );

CREATE INDEX ix_products_performance1 ON products ( parent_product_id );

ALTER TABLE products
	ADD COLUMN parent_or_self_id INT;

-- Populate after data import

UPDATE products SET parent_or_self_id = COALESCE(parent_product_id, id);

CREATE INDEX ix_products_performance2 ON products ( parent_or_self_id, active );

CREATE INDEX ix_stock_log_performance1 ON stock_log ( stock_id(191), transaction_type(191), amount );

CREATE INDEX ix_stock_log_performance2 ON stock_log ( product_id, best_before_date, purchased_date, transaction_type(191), stock_id(191), undone );

CREATE INDEX ix_cache__quantity_unit_conversions_resolved_performance1 ON cache__quantity_unit_conversions_resolved ( product_id, from_qu_id, to_qu_id );
