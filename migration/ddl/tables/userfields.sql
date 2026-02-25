CREATE TABLE userfields (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	entity TEXT NOT NULL,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	type TEXT NOT NULL,
	show_as_column_in_tables TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */, config TEXT, sort_number INTEGER, input_required TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(input_required IN (0, 1)) */, default_value TEXT,

	UNIQUE(entity, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
