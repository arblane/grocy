CREATE TABLE IF NOT EXISTS "chores" (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	period_type TEXT NOT NULL,
	period_days INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, period_config TEXT, track_date_only TINYINT DEFAULT 0, rollover TINYINT DEFAULT 0, assignment_type TEXT, assignment_config TEXT, next_execution_assigned_to_user_id INT, consume_product_on_execution TINYINT NOT NULL DEFAULT 0, product_id TINYINT, product_amount REAL, period_interval INTEGER NOT NULL DEFAULT 1 /* REVIEW: CHECK */ CHECK(period_interval > 0), active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */, start_date DATETIME, rescheduled_date DATETIME, rescheduled_next_execution_assigned_to_user_id INT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
