-- Post-import computed column updates
-- Run after data import but before triggers are re-enabled

-- Add parent_or_self_id column if not exists
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'products' AND COLUMN_NAME = 'parent_or_self_id');

SET @sql = IF(@col_exists = 0, 
  'ALTER TABLE products ADD COLUMN parent_or_self_id INT;',
  'SELECT "Column parent_or_self_id already exists" as info;');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Populate parent_or_self_id (computed from parent_product_id or id)
UPDATE products SET parent_or_self_id = COALESCE(parent_product_id, id);
