CREATE TABLE userentities (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	description TEXT,
	show_in_sidebar_menu TINYINT NOT NULL DEFAULT 1,
	icon_css_class TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
