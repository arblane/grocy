CREATE TABLE stock (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,
	stock_id TEXT NOT NULL,
	price DECIMAL(15, 2),
	open TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(open IN (0, 1)) */,
	opened_date DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, location_id INTEGER, shopping_location_id INTEGER, note TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
