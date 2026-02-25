
CREATE OR REPLACE VIEW users_dto AS
SELECT
	id,
	username,
	first_name,
	last_name,
	row_created_timestamp,
	(CASE
		WHEN COALESCE(first_name, '') = '' AND COALESCE(last_name, '') != '' THEN last_name
		WHEN COALESCE(last_name, '') = '' AND COALESCE(first_name, '') != '' THEN first_name
		WHEN COALESCE(last_name, '') != '' AND COALESCE(first_name, '') != '' THEN CONCAT(first_name, ' ', last_name)
		ELSE username
	END
	) AS display_name,
	picture_file_name
FROM users
/* users_dto(id,username,first_name,last_name,row_created_timestamp,display_name,picture_file_name) */;;
