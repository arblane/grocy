-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW uihelper_user_permissions AS
SELECT
	ph.id AS id,
	u.id AS user_id,
	ph.name AS permission_name,
	ph.id AS permission_id,
	(ph.name IN (
			SELECT pc.permission_name
			FROM user_permissions_resolved pc
			WHERE pc.user_id = u.id
		)
	) AS has_permission,
	ph.parent AS parent
FROM users u, permission_hierarchy ph
/* uihelper_user_permissions(id,user_id,permission_name,permission_id,has_permission,parent) */;;
