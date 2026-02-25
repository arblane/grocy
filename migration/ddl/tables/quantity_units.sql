CREATE TABLE quantity_units (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, name_plural TEXT, plural_forms TEXT, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
