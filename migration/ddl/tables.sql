CREATE TABLE migrations (migration INT NOT NULL PRIMARY KEY AUTO_INCREMENT, execution_time_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE locations (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, is_freezer TINYINT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE quantity_units (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, name_plural TEXT, plural_forms TEXT, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS "chores" (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	period_type TEXT NOT NULL,
	period_days INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, period_config TEXT, track_date_only TINYINT DEFAULT 0, rollover TINYINT DEFAULT 0, assignment_type TEXT, assignment_config TEXT, next_execution_assigned_to_user_id INT, consume_product_on_execution TINYINT NOT NULL DEFAULT 0, product_id TINYINT, product_amount REAL, period_interval INTEGER NOT NULL DEFAULT 1 /* REVIEW: CHECK */ CHECK(period_interval > 0), active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */, start_date DATETIME, rescheduled_date DATETIME, rescheduled_next_execution_assigned_to_user_id INT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE batteries (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	used_in TEXT,
	charge_interval_days INTEGER NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE recipes (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, picture_file_name TEXT, base_servings INTEGER DEFAULT 1, desired_servings INTEGER DEFAULT 1, not_check_shoppinglist TINYINT NOT NULL DEFAULT 0, type TEXT DEFAULT 'normal', product_id INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE users (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	username TEXT NOT NULL UNIQUE,
	first_name TEXT,
	last_name TEXT,
	password TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, picture_file_name TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE sessions (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	session_key TEXT NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE api_keys (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	api_key TEXT NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, key_type TEXT NOT NULL DEFAULT 'default', description TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE chores_log (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	chore_id INTEGER NOT NULL,
	tracked_time DATETIME,
	done_by_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, undone TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(undone IN (0, 1)) */, undone_timestamp DATETIME, skipped TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(skipped IN (0, 1)) */, scheduled_execution_time DATETIME) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE task_categories (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE product_groups (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_settings (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	user_id INTEGER NOT NULL,
	key TEXT NOT NULL,
	value TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,
	row_updated_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(user_id, key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE equipment (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	instruction_manual_file_name TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE recipes_nestings (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	includes_recipe_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */, servings INTEGER DEFAULT 1,

	UNIQUE(recipe_id, includes_recipe_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE recipes_pos (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	amount REAL NOT NULL DEFAULT 0,
	note TEXT,
	qu_id INTEGER,
	only_check_single_unit_in_stock TINYINT NOT NULL DEFAULT 0,
	ingredient_group TEXT,
	not_check_stock_fulfillment TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, variable_amount TEXT, price_factor REAL NOT NULL DEFAULT 1, round_up TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(round_up IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE stock (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,
	stock_id TEXT NOT NULL,
	price DECIMAL(15, 2),
	open TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(open IN (0, 1)) */,
	opened_date DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, location_id INTEGER, shopping_location_id INTEGER, note TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE shopping_list (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INTEGER,
	note TEXT,
	amount DECIMAL(15, 2) NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, shopping_list_id INT DEFAULT 1, done INT DEFAULT 0, qu_id INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE shopping_lists (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE userfields (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	entity TEXT NOT NULL,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	type TEXT NOT NULL,
	show_as_column_in_tables TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */, config TEXT, sort_number INTEGER, input_required TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(input_required IN (0, 1)) */, default_value TEXT,

	UNIQUE(entity, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE quantity_unit_conversions (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	from_qu_id INT NOT NULL,
	to_qu_id INT NOT NULL,
	factor REAL NOT NULL,
	product_id INT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE userentities (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	description TEXT,
	show_in_sidebar_menu TINYINT NOT NULL DEFAULT 1,
	icon_css_class TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE userobjects (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	userentity_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE meal_plan (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	day DATE NOT NULL,
	type TEXT DEFAULT 'recipe',
	recipe_id INTEGER,
	recipe_servings INTEGER DEFAULT 1,
	note TEXT,
	product_id INTEGER,
	product_amount REAL DEFAULT 0,
	product_qu_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, done TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(done IN (0, 1)) */, section_id INTEGER NOT NULL DEFAULT -1) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE shopping_locations (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE product_barcodes (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT NOT NULL,
	barcode TEXT NOT NULL,
	qu_id INT,
	amount REAL,
	shopping_location_id INTEGER,
	last_price DECIMAL(15, 2),
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, note TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_permissions
(
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	permission_id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,

	UNIQUE (user_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE permission_hierarchy
(
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	parent INTEGER NULL -- If the user has the parent permission, the user also has the child permission
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE tasks (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	due_date DATETIME,
	done TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(done IN (0, 1)) */,
	done_timestamp DATETIME,
	category_id INTEGER,
	assigned_to_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE battery_charge_cycles (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	battery_id INTEGER NOT NULL,
	tracked_time DATETIME,
	undone TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(undone IN (0, 1)) */,
	undone_timestamp DATETIME,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE meal_plan_sections (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	sort_number INTEGER,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, time_info TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE stock_log (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE,
	used_date DATE,
	spoiled INTEGER NOT NULL DEFAULT 0,
	stock_id TEXT NOT NULL,
	transaction_type TEXT NOT NULL,
	price DECIMAL(15, 2),
	undone TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(undone IN (0, 1)) */,
	undone_timestamp DATETIME,
	opened_date DATETIME,
	location_id INTEGER,
	recipe_id INTEGER,
	correlation_id TEXT,
	transaction_id TEXT,
	stock_row_id INTEGER,
	shopping_location_id INTEGER,
	user_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, note TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE userfield_values (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	field_id INTEGER NOT NULL,
	object_id TEXT NOT NULL,
	value TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */,

	UNIQUE(field_id, object_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE products (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	product_group_id INTEGER,
	active TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(active IN (0, 1)) */,
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
	due_type TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted to ENUM: CHECK(due_type IN (1, 2)) */,
	quick_consume_amount REAL NOT NULL DEFAULT 1,
	hide_on_stock_overview TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(hide_on_stock_overview IN (0, 1)) */,
	default_stock_label_type INTEGER NOT NULL DEFAULT 0,
	should_not_be_frozen TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(should_not_be_frozen IN (0, 1)) */,
	treat_opened_as_out_of_stock TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted: CHECK(treat_opened_as_out_of_stock IN (0, 1)) */,
	no_own_stock TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(no_own_stock IN (0, 1)) */,
	default_consume_location_id INTEGER,
	move_on_open TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(move_on_open IN (0, 1)) */,
	row_created_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */
, qu_id_consume INTEGER, auto_reprint_stock_label TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(auto_reprint_stock_label IN (0, 1)) */, quick_open_amount REAL NOT NULL DEFAULT 1, qu_id_price INTEGER, disable_open TINYINT NOT NULL DEFAULT 0 /* REVIEW: CHECK */ /* CHECK converted: CHECK(disable_open IN (0, 1)) */, default_purchase_price_type TINYINT NOT NULL DEFAULT 1 /* REVIEW: CHECK */ /* CHECK converted to ENUM: CHECK(default_purchase_price_type IN (1, 2, 3)) */) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cache__quantity_unit_conversions_resolved (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	from_qu_id INT,
	from_qu_name TEXT,
	from_qu_name_plural TEXT,
	to_qu_id INT,
	to_qu_name TEXT,
	to_qu_name_plural TEXT,
	factor TEXT,
	path TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cache__products_average_price (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	price DECIMAL(15, 2),

	UNIQUE(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cache__products_last_purchased (
	id INT NOT NULL PRIMARY KEY AUTO_INCREMENT UNIQUE,
	product_id INT,
	amount DECIMAL(15, 2),
	best_before_date DATE,
	purchased_date DATE,
	price DECIMAL(15, 2),
	location_id INT,
	shopping_location_id INT,

	UNIQUE(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
