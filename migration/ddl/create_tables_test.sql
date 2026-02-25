CREATE TABLE migrations (
	migration INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	execution_time_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE locations (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, is_freezer TINYINT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE quantity_units (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, name_plural TEXT, plural_forms TEXT, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE IF NOT EXISTS `chores` (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	period_type TEXT NOT NULL,
	period_days INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, period_config TEXT, track_date_only TINYINT DEFAULT 0, rollover TINYINT DEFAULT 0, assignment_type TEXT, assignment_config TEXT, next_execution_assigned_to_user_id INT, consume_product_on_execution TINYINT NOT NULL DEFAULT 0, product_id TINYINT, product_amount REAL, period_interval INTEGER NOT NULL DEFAULT 1, active TINYINT NOT NULL DEFAULT 1, start_date DATETIME, rescheduled_date DATETIME, rescheduled_next_execution_assigned_to_user_id INT);
CREATE TABLE batteries (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	used_in TEXT,
	charge_interval_days INTEGER NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE recipes (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name TEXT NOT NULL,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, picture_file_name TEXT, base_servings INTEGER DEFAULT 1, desired_servings INTEGER DEFAULT 1, not_check_shoppinglist TINYINT NOT NULL DEFAULT 0, `type` VARCHAR(255) DEFAULT 'normal', product_id INTEGER);
CREATE TABLE users (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	username VARCHAR(255) NOT NULL UNIQUE,
	first_name TEXT,
	last_name TEXT,
	password TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, picture_file_name TEXT);
CREATE TABLE sessions (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	session_key VARCHAR(255) NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE api_keys (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	api_key VARCHAR(255) NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, key_type VARCHAR(255) NOT NULL DEFAULT 'default', description TEXT);
CREATE TABLE chores_log (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	chore_id INTEGER NOT NULL,
	tracked_time DATETIME,
	done_by_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, undone TINYINT NOT NULL DEFAULT 0, undone_timestamp DATETIME, skipped TINYINT NOT NULL DEFAULT 0, scheduled_execution_time DATETIME);
CREATE TABLE task_categories (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE product_groups (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE user_settings (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	user_id INTEGER NOT NULL,
	`key` VARCHAR(255) NOT NULL,
	value TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
	row_updated_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

	UNIQUE(user_id, `key`)
);
CREATE TABLE equipment (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	instruction_manual_file_name TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE recipes_nestings (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	recipe_id INTEGER NOT NULL,
	includes_recipe_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, servings INTEGER DEFAULT 1,

	UNIQUE(recipe_id, includes_recipe_id)
);
CREATE TABLE recipes_pos (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	recipe_id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	amount REAL NOT NULL DEFAULT 0,
	note TEXT,
	qu_id INTEGER,
	only_check_single_unit_in_stock TINYINT NOT NULL DEFAULT 0,
	ingredient_group TEXT,
	not_check_stock_fulfillment TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, variable_amount TEXT, price_factor REAL NOT NULL DEFAULT 1, round_up TINYINT NOT NULL DEFAULT 0);
CREATE TABLE stock (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE DEFAULT CURRENT_DATE,
	stock_id TEXT NOT NULL,
	price DECIMAL(15, 2),
	`open` TINYINT NOT NULL DEFAULT 0,
	opened_date DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, location_id INTEGER, shopping_location_id INTEGER, note TEXT);
CREATE TABLE shopping_list (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INTEGER,
	note TEXT,
	amount DECIMAL(15, 2) NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, shopping_list_id INT DEFAULT 1, `done` INT DEFAULT 0, qu_id INTEGER);
CREATE TABLE shopping_lists (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE userfields (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	entity VARCHAR(255) NOT NULL,
	name VARCHAR(255) NOT NULL,
	caption TEXT NOT NULL,
	`type` TEXT NOT NULL,
	show_as_column_in_tables TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, config TEXT, sort_number INTEGER, input_required TINYINT NOT NULL DEFAULT 0, default_value TEXT,

	UNIQUE(entity, name)
);
CREATE TABLE quantity_unit_conversions (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	from_qu_id INT NOT NULL,
	to_qu_id INT NOT NULL,
	factor REAL NOT NULL,
	product_id INT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE userentities (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL,
	caption TEXT NOT NULL,
	description TEXT,
	show_in_sidebar_menu TINYINT NOT NULL DEFAULT 1,
	icon_css_class TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,

	UNIQUE(name)
);
CREATE TABLE userobjects (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	userentity_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE meal_plan (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	day DATE NOT NULL,
	`type` VARCHAR(255) DEFAULT 'recipe',
	recipe_id INTEGER,
	recipe_servings INTEGER DEFAULT 1,
	note TEXT,
	product_id INTEGER,
	product_amount REAL DEFAULT 0,
	product_qu_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, `done` TINYINT NOT NULL DEFAULT 0, section_id INTEGER NOT NULL DEFAULT -1);
CREATE TABLE shopping_locations (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, active TINYINT NOT NULL DEFAULT 1);
CREATE TABLE product_barcodes (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INT NOT NULL,
	barcode TEXT NOT NULL,
	qu_id INT,
	amount REAL,
	shopping_location_id INTEGER,
	last_price DECIMAL(15, 2),
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
, note TEXT);
CREATE TABLE user_permissions
(
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	permission_id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,

	UNIQUE (user_id, permission_id)
);
CREATE TABLE permission_hierarchy
(
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	parent INTEGER NULL
);
CREATE TABLE tasks (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name TEXT NOT NULL,
	description TEXT,
	due_date DATETIME,
	`done` TINYINT NOT NULL DEFAULT 0,
	done_timestamp DATETIME,
	category_id INTEGER,
	assigned_to_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE battery_charge_cycles (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	battery_id INTEGER NOT NULL,
	tracked_time DATETIME,
	undone TINYINT NOT NULL DEFAULT 0,
	undone_timestamp DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE meal_plan_sections (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) NOT NULL UNIQUE,
	sort_number INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
	time_info TEXT);
CREATE TABLE stock_log (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE,
	used_date DATE,
	spoiled INTEGER NOT NULL DEFAULT 0,
	stock_id TEXT NOT NULL,
	transaction_type TEXT NOT NULL,
	price DECIMAL(15, 2),
	undone TINYINT NOT NULL DEFAULT 0,
	undone_timestamp DATETIME,
	opened_date DATETIME,
	location_id INTEGER,
	recipe_id INTEGER,
	correlation_id TEXT,
	transaction_id TEXT,
	stock_row_id INTEGER,
	shopping_location_id INTEGER,
	user_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
	note TEXT);
CREATE TABLE userfield_values (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	field_id INTEGER NOT NULL,
	object_id VARCHAR(255) NOT NULL,
	value TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,

	UNIQUE(field_id, object_id)
);
CREATE TABLE products (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	name VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL UNIQUE,
	description TEXT,
	product_group_id INTEGER,
	active TINYINT NOT NULL DEFAULT 1,
	location_id INTEGER NOT NULL,
	shopping_location_id INTEGER,
	qu_id_purchase INTEGER NOT NULL,
	qu_id_stock INTEGER NOT NULL,
	min_stock_amount INTEGER NOT NULL DEFAULT 0,
	default_best_before_days INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_open INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_freezing INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_thawing INTEGER NOT NULL DEFAULT 0,
	picture_file_name TEXT,
	enable_tare_weight_handling TINYINT NOT NULL DEFAULT 0,
	tare_weight REAL NOT NULL DEFAULT 0,
	not_check_stock_fulfillment_for_recipes TINYINT DEFAULT 0,
	parent_product_id INT,
	calories INTEGER,
	cumulate_min_stock_amount_of_sub_products TINYINT DEFAULT 0,
	due_type TINYINT NOT NULL DEFAULT 1,
	quick_consume_amount REAL NOT NULL DEFAULT 1,
	hide_on_stock_overview TINYINT NOT NULL DEFAULT 0,
	default_stock_label_type INTEGER NOT NULL DEFAULT 0,
	should_not_be_frozen TINYINT NOT NULL DEFAULT 0,
	treat_opened_as_out_of_stock TINYINT NOT NULL DEFAULT 1,
	no_own_stock TINYINT NOT NULL DEFAULT 0,
	default_consume_location_id INTEGER,
	move_on_open TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
	qu_id_consume INTEGER, auto_reprint_stock_label TINYINT NOT NULL DEFAULT 0, quick_open_amount REAL NOT NULL DEFAULT 1, qu_id_price INTEGER, disable_open TINYINT NOT NULL DEFAULT 0, default_purchase_price_type TINYINT NOT NULL DEFAULT 1);
CREATE TABLE cache__quantity_unit_conversions_resolved (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INT,
	from_qu_id INT,
	from_qu_name TEXT,
	from_qu_name_plural TEXT,
	to_qu_id INT,
	to_qu_name TEXT,
	to_qu_name_plural TEXT,
	factor TEXT,
	path TEXT
);
CREATE TABLE cache__products_average_price (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INT,
	price DECIMAL(15, 2),

	UNIQUE(product_id)
);
CREATE TABLE cache__products_last_purchased (
	id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
	product_id INT,
	amount DECIMAL(15, 2),
	best_before_date DATE,
	purchased_date DATE,
	price DECIMAL(15, 2),
	location_id INT,
	shopping_location_id INT,

	UNIQUE(product_id)
);
