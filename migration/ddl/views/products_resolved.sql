-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW products_resolved AS
SELECT
    CASE
        WHEN p.parent_product_id IS NULL THEN
            p.id
        ELSE
            p.parent_product_id
    END AS parent_product_id,
    p.id as sub_product_id
FROM products p
WHERE p.active = 1
/* products_resolved(parent_product_id,sub_product_id) */;;
