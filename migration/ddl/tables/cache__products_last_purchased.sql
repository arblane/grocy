CREATE TABLE cache__products_last_purchased (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	amount DECIMAL(15, 2),
	best_before_date DATE,
	purchased_date DATE,
	price DECIMAL(15, 2),
	location_id INT,
	shopping_location_id INT,

	UNIQUE(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
