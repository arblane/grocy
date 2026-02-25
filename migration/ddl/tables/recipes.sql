CREATE TABLE recipes (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, picture_file_name TEXT, base_servings INTEGER DEFAULT 1, desired_servings INTEGER DEFAULT 1, not_check_shoppinglist TINYINT NOT NULL DEFAULT 0, type TEXT DEFAULT 'normal', product_id INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
