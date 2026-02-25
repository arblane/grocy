CREATE TABLE users (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	username TEXT NOT NULL UNIQUE,
	first_name TEXT,
	last_name TEXT,
	password TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, picture_file_name TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
