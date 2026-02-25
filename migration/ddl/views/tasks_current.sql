-- Converted view (MariaDB-compatible)

CREATE OR REPLACE VIEW tasks_current AS
SELECT *
FROM tasks
WHERE done = 0
/* tasks_current(id,name,description,due_date,done,done_timestamp,category_id,assigned_to_user_id,row_created_timestamp) */;;
