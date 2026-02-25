CREATE TABLE user_settings (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	user_id INTEGER NOT NULL,
	key TEXT NOT NULL,
	value TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,
	row_updated_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(user_id, key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
