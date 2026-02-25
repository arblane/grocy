CREATE TABLE cache__products_average_price (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	price DECIMAL(15, 2),

	UNIQUE(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
