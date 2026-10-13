-- Written after the database switches to WAL and copied before it is checkpointed, so these rows live only in
-- places.sqlite-wal, as recent changes do while Firefox runs.
INSERT INTO moz_places VALUES (9, 'https://wiki.example.org/', 'Team Wiki', 400, 0);
INSERT INTO moz_bookmarks VALUES (3, 1, 9, 'Team Wiki');
