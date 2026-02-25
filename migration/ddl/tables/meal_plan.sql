CREATE TABLE meal_plan (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	day DATE NOT NULL,
	type TEXT DEFAULT 'recipe',
	recipe_id INTEGER,
	recipe_servings INTEGER DEFAULT 1,
	note TEXT,
	product_id INTEGER,
	product_amount REAL DEFAULT 0,
	product_qu_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, done TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(done IN (0, 1)) */, section_id INTEGER NOT NULL DEFAULT -1) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
