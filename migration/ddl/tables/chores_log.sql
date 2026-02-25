CREATE TABLE chores_log (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	chore_id INTEGER NOT NULL,
	tracked_time DATETIME,
	done_by_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, undone TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(undone IN (0, 1)) */, undone_timestamp DATETIME, skipped TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(skipped IN (0, 1)) */, scheduled_execution_time DATETIME) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
