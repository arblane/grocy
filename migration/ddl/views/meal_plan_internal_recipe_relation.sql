-- Refine notes: Rewrote 1 '||' concatenation(s) into CONCAT(); STRFTIME() occurrences left for manual mapping to DATE_FORMAT()
-- NOTE: STRFTIME() detected — manual mapping to DATE_FORMAT() may be required
-- Converted view (MariaDB-compatible)

-- Flags: STRFTIME() used — manual review, CONCAT(', ') -> CONCAT() (best-effort)
CREATE OR REPLACE VIEW meal_plan_internal_recipe_relation AS
-- Relation between a meal plan (day) and the corresponding internal recipe(s)

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = CAST(mp.day AS CHAR)
	AND r.type = 'mealplan-day'

UNION

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = TRIM(LEADING '0' FROM DATE_FORMAT(mp.day, '%Y-%v'))
	AND r.type = 'mealplan-week'

UNION

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = CONCAT(CAST(mp.day AS CHAR), '#', CAST(mp.id AS CHAR))
	AND r.type = 'mealplan-shadow'
/* meal_plan_internal_recipe_relation(day,recipe_id) */;;
