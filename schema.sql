CREATE TABLE IF NOT EXISTS `events` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `when` int(10) unsigned NOT NULL,
  `chan` varchar(255) NOT NULL,
  `user` varchar(255) NOT NULL,
  `event` varchar(255) NOT NULL,
  `text` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `chan` (`chan`,`when`),
  FULLTEXT KEY `text` (`text`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

