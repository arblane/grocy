CREATE TABLE recipes_pos (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	amount REAL NOT NULL DEFAULT 0,
	note TEXT,
	qu_id INTEGER,
	only_check_single_unit_in_stock TINYINT NOT NULL DEFAULT 0,
	ingredient_group TEXT,
	not_check_stock_fulfillment TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, variable_amount TEXT, price_factor REAL NOT NULL DEFAULT 1, round_up TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(round_up IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
