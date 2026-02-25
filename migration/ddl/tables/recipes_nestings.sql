CREATE TABLE recipes_nestings (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	includes_recipe_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */, servings INTEGER DEFAULT 1,

	UNIQUE(recipe_id, includes_recipe_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
