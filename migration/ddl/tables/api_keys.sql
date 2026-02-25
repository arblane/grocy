CREATE TABLE api_keys (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	api_key TEXT NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, key_type TEXT NOT NULL DEFAULT 'default', description TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
