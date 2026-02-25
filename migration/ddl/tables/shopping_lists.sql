CREATE TABLE shopping_lists (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
