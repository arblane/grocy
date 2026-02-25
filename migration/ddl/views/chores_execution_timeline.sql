-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW chores_execution_timeline AS
SELECT
	cl.chore_id,
	cl.tracked_time,
	(SELECT tracked_time FROM chores_log WHERE chore_id = cl.chore_id AND undone = 0 AND tracked_time < cl.tracked_time ORDER BY tracked_time DESC LIMIT 1) AS tracked_time_before,
	TIMESTAMPDIFF(
		HOUR,
		(SELECT tracked_time FROM chores_log WHERE chore_id = cl.chore_id AND undone = 0 AND tracked_time < cl.tracked_time ORDER BY tracked_time DESC LIMIT 1),
		cl.tracked_time
	) AS frequency_hours
FROM chores_log cl
WHERE cl.undone = 0
/* chores_execution_timeline(chore_id,tracked_time,tracked_time_before,frequency_hours) */;;
