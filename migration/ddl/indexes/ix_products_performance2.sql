CREATE INDEX ix_products_performance2 ON products ( CASE WHEN parent_product_id IS NULL THEN id ELSE parent_product_id END, active );
