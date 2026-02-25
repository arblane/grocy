CREATE TABLE locations (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, is_freezer TINYINT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
