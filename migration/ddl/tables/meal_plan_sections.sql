CREATE TABLE meal_plan_sections (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	sort_number INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, time_info TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
