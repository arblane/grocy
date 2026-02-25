CREATE TABLE quantity_unit_conversions (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	from_qu_id INT NOT NULL,
	to_qu_id INT NOT NULL,
	factor REAL NOT NULL,
	product_id INT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
