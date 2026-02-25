-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW permission_tree AS
WITH RECURSIVE perm AS (
	SELECT id AS root, id AS child, name, parent
	FROM permission_hierarchy
	UNION
	SELECT perm.root, ph.id, ph.name, ph.id
	FROM permission_hierarchy ph, perm
	WHERE ph.parent = perm.child
)
SELECT root AS id, name AS name
FROM perm
/* permission_tree(id,name) */;;
