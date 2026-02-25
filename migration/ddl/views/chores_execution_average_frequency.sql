-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW chores_execution_average_frequency AS
SELECT
	cet.chore_id,
	AVG(cet.frequency_hours) AS average_frequency_hours
FROM chores_execution_timeline cet
GROUP BY cet.chore_id
/* chores_execution_average_frequency(chore_id,average_frequency_hours) */;;
