-- Refine notes: Rewrote 1 '||' concatenation(s) into CONCAT()
-- Converted view (MariaDB-compatible)

-- Flags: CONCAT(', ') -> CONCAT() (best-effort)
CREATE OR REPLACE VIEW chores_assigned_users_resolved AS
SELECT
	c.id AS chore_id,
	u.id AS user_id
FROM chores c
JOIN users u
	ON CONCAT(',', c.assignment_config, ',') LIKE CONCAT('%,', CAST(u.id AS CHAR), ',%')
WHERE c.active = 1
/* chores_assigned_users_resolved(chore_id,user_id) */;;
