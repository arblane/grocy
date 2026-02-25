CREATE TABLE shopping_list (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INTEGER,
	note TEXT,
	amount DECIMAL(15, 2) NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, shopping_list_id INT DEFAULT 1, done INT DEFAULT 0, qu_id INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
