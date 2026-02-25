CREATE TABLE userobjects (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	userentity_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
