-- The tables and columns of Firefox's places.sqlite that firefox-tab reads, with made-up rows.
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT, frecency INTEGER, hidden INTEGER DEFAULT 0);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, title TEXT);
CREATE TABLE moz_origins (id INTEGER PRIMARY KEY, prefix TEXT, host TEXT, frecency INTEGER);
INSERT INTO moz_places VALUES
  (1, 'https://docs.example.com/start', 'Example Docs - Getting started', 500, 0),
  (2, 'https://tubesite.example/', 'TubeSite', 900, 0),
  (3, 'https://tubesite.example/watch?v=1', 'Funny cat video - TubeSite', 300, 0),
  (4, 'https://code.example.org/', 'Code Hub', 800, 0),
  (5, 'https://news.example.net/', 'Daily Planet News', 200, 0),
  (6, 'https://code.example.org/acme/widgets', 'acme/widgets: Widgets for everyone', 100, 0),
  (7, 'https://tracker.example/pixel', 'Code Hub pixel', 50, 1),
  (8, 'place:sort=8', 'Code Hub recent', 999, 0);
INSERT INTO moz_bookmarks VALUES (1, 1, 5, 'Daily Planet'), (2, 2, NULL, 'Code Hub folder');
INSERT INTO moz_origins VALUES
  (1, 'https://', 'tubesite.example', 900),
  (2, 'https://', 'code.example.org', 800),
  (3, 'https://', 'docs.example.com', 500),
  (4, 'https://', 'news.example.net', 200);
