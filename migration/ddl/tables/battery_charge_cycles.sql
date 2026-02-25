CREATE TABLE battery_charge_cycles (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	battery_id INTEGER NOT NULL,
	tracked_time DATETIME,
	undone TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(undone IN (0, 1)) */,
	undone_timestamp DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
