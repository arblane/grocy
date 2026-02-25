CREATE TABLE product_barcodes (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT NOT NULL,
	barcode TEXT NOT NULL,
	qu_id INT,
	amount REAL,
	shopping_location_id INTEGER,
	last_price DECIMAL(15, 2),
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, note TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
