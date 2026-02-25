-- Refine notes: Rewrote 35 '||' concatenation(s) into CONCAT(); STRFTIME() occurrences left for manual mapping to DATE_FORMAT()
-- NOTE: STRFTIME() detected — manual mapping to DATE_FORMAT() may be required
-- Converted view (MariaDB-compatible)

-- Flags: IFNULL -> COALESCE, STRFTIME() used — manual review
CREATE OR REPLACE VIEW chores_current AS
SELECT
	x.chore_id AS id, -- Dummy, LessQL needs an id column
	x.chore_id,
	x.chore_name,
	x.last_tracked_time,
	CASE
		WHEN x.rollover = 1 AND NOW() > x.next_estimated_execution_time THEN
			CASE WHEN COALESCE(x.track_date_only, 0) = 1 THEN
				TIMESTAMP(DATE(NOW()), '23:59:59')
			ELSE
				TIMESTAMP(DATE(NOW()), TIME(x.next_estimated_execution_time))
			END
		ELSE
			CASE WHEN COALESCE(x.track_date_only, 0) = 1 THEN
				TIMESTAMP(DATE(x.next_estimated_execution_time), '23:59:59')
			ELSE
				x.next_estimated_execution_time
			END
	END AS next_estimated_execution_time,
	x.track_date_only,
	x.next_execution_assigned_to_user_id,
	CASE WHEN COALESCE(x.rescheduled_date, '') != '' THEN 1 ELSE 0 END AS is_rescheduled,
	CASE WHEN COALESCE(x.rescheduled_next_execution_assigned_to_user_id, '') != '' THEN 1 ELSE 0 END AS is_reassigned
FROM (

SELECT
	h.id AS chore_id,
	h.name AS chore_name,
	MAX(l.tracked_time) AS last_tracked_time,
	CASE WHEN COALESCE(h.rescheduled_date, '') != '' THEN
		h.rescheduled_date
	ELSE
		CASE WHEN MAX(l.tracked_time) IS NULL AND h.period_type != 'manually' THEN
			h.start_date
		ELSE
			CASE h.period_type
				WHEN 'manually' THEN NULL
				WHEN 'hourly' THEN DATE_ADD(MAX(l.tracked_time), INTERVAL h.period_interval HOUR)
				WHEN 'daily' THEN TIMESTAMP(
					DATE(DATE_ADD(MAX(l.tracked_time), INTERVAL h.period_interval DAY)),
					TIME(h.start_date)
				)
				WHEN 'weekly' THEN LEAST(
					CASE WHEN INSTR(period_config, 'sunday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 6 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'monday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 0 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'tuesday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 1 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'wednesday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 2 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'thursday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 3 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'friday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 4 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END,
					CASE WHEN INSTR(period_config, 'saturday') > 0 THEN
						DATE_ADD(
							DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
								INTERVAL (1 + (h.period_interval - 1) * 7) DAY
							),
							INTERVAL MOD(7 + 5 - WEEKDAY(
								DATE_ADD((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1),
									INTERVAL (1 + (h.period_interval - 1) * 7) DAY
								)
							), 7) DAY
						)
					ELSE '9999-12-31' END
				)
				WHEN 'monthly' THEN DATE_ADD(
					DATE_ADD(
						DATE_SUB(DATE(MAX(l.tracked_time)), INTERVAL DAYOFMONTH(MAX(l.tracked_time)) - 1 DAY),
						INTERVAL h.period_interval MONTH
					),
					INTERVAL (h.period_days - 1) DAY
				)
				WHEN 'yearly' THEN TIMESTAMP(
					CONCAT(
						YEAR(DATE_ADD(MAX(l.tracked_time), INTERVAL h.period_interval YEAR)),
						DATE_FORMAT(h.start_date, '-%m-%d '),
						DATE_FORMAT(DATE_ADD(MAX(l.tracked_time), INTERVAL h.period_interval YEAR), '%H:%i:%s')
					)
				)
				WHEN 'adaptive' THEN DATE_ADD(
					MAX(l.tracked_time),
					INTERVAL COALESCE((SELECT average_frequency_hours FROM chores_execution_average_frequency WHERE chore_id = h.id), 0) * 3600 SECOND
				)
			END
		END
	END AS next_estimated_execution_time,
	h.track_date_only,
	h.rollover,
	h.next_execution_assigned_to_user_id,
	h.rescheduled_date,
	h.rescheduled_next_execution_assigned_to_user_id
FROM chores h
LEFT JOIN chores_log l
	ON h.id = l.chore_id
	AND l.undone = 0
WHERE h.active = 1
GROUP BY h.id, h.name, h.period_days
) x
/* chores_current(id,chore_id,chore_name,last_tracked_time,next_estimated_execution_time,track_date_only,next_execution_assigned_to_user_id,is_rescheduled,is_reassigned) */;;
