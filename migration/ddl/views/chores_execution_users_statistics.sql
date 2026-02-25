-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW chores_execution_users_statistics AS
SELECT
	c.id AS id, -- Dummy, LessQL needs an id column
	c.id AS chore_id,
	caur.user_id AS user_id,
	(SELECT COUNT(1) FROM chores_log WHERE chore_id = c.id AND done_by_user_id = caur.user_id AND undone = 0) AS execution_count
FROM chores c
JOIN chores_assigned_users_resolved caur
	ON c.id = caur.chore_id
GROUP BY c.id, caur.user_id
/* chores_execution_users_statistics(id,chore_id,user_id,execution_count) */;;
