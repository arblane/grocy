CREATE TABLE userfield_values (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	field_id INTEGER NOT NULL,
	object_id TEXT NOT NULL,
	value TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(field_id, object_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
