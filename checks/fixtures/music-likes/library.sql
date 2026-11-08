CREATE TABLE items (
  id INTEGER PRIMARY KEY, path TEXT, title TEXT, artist TEXT, albumartist TEXT,
  album TEXT, isrc TEXT, mb_trackid TEXT, length REAL, format TEXT, subtitle TEXT, bitrate INTEGER
);
CREATE TABLE item_attributes (entity_id INTEGER, key TEXT, value TEXT);
INSERT INTO items VALUES
 (1,'MP3/Showtek/2010 - Analogue Players In A Digital World/01 Hear This.mp3',
  'Hear This','Showtek','Showtek','Analogue Players In A Digital World','ITC941001118','',222.0,'MP3',NULL,320000),
 (2,'FLAC/Headhunterz/2024 - Studio Sessions/01 Spaceship (Original Mix).flac',
  'Spaceship (Original Mix)','Headhunterz','Headhunterz','Studio Sessions','','',212.0,'FLAC',NULL,0),
 (3,'MP3/Artist/Album/01 Feeling Fly (Extended Mix).mp3',
  'Feeling Fly (Extended Mix)','Artist','Artist','Album','','',180.0,'MP3',NULL,320000),
 (4,'FLAC/Both Artist/Both Album/01 Already Both.flac',
  'Already Both','Both Artist','Both Artist','Both Album','USABC0012345','',200.0,'FLAC',NULL,0),
 (5,'MP3/Both Artist/Both Album/01 Already Both.mp3',
  'Already Both','Both Artist','Both Artist','Both Album','USABC0012345','',200.0,'MP3',NULL,320000);
