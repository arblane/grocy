DROP FUNCTION IF EXISTS grocy_user_setting;
CREATE FUNCTION grocy_user_setting(setting_key VARCHAR(255))
RETURNS VARCHAR(255)
READS SQL DATA
RETURN (
	SELECT value
	FROM user_settings
	WHERE user_id = 1
		AND `key` = setting_key
	LIMIT 1
);
