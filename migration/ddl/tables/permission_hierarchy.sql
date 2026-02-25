CREATE TABLE permission_hierarchy
(
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	parent INTEGER NULL -- If the user has the parent permission, the user also has the child permission
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
