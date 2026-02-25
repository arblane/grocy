CREATE TABLE user_permissions
(
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	permission_id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,

	UNIQUE (user_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
