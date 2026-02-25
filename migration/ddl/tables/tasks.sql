CREATE TABLE tasks (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	due_date DATETIME,
	done TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(done IN (0, 1)) */,
	done_timestamp DATETIME,
	category_id INTEGER,
	assigned_to_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
