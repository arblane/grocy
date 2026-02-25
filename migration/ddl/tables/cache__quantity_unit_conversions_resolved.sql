CREATE TABLE cache__quantity_unit_conversions_resolved (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	from_qu_id INT,
	from_qu_name TEXT,
	from_qu_name_plural TEXT,
	to_qu_id INT,
	to_qu_name TEXT,
	to_qu_name_plural TEXT,
	factor TEXT,
	path TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
