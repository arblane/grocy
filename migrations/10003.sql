ALTER TABLE locations ADD COLUMN parent_location_id INT NULL REFERENCES locations(id);
