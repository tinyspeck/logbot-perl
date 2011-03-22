#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use DBI;

use POE;
use POE::Component::IRC::Common qw(parse_user l_irc);
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::AutoJoin;
use IO::Socket::INET;

use constant {
	IRC_NICKNAME	=> 'logbot',
	IRC_SERVER_HOST	=> 'irc.company.com',
	IRC_SERVER_PASS	=> undef,
	IRC_CHANNELS	=> qw( #foo #bar ),

	UDP_PORT	=> '8675',
	DEFAULT_CHANNEL => '#foo',

	DB_DSN		=> "DBI:mysql:database=logbot;host=localhost;port=3306";
	DB_USER		=> 'root',
	DB_PASS		=> 'password',
};


#
# Below here be dragons...
#

use constant {
	EVENT_JOIN	=> 'join',
	EVENT_PART	=> 'part',
	EVENT_TEXT	=> 'text',
	EVENT_TOPIC	=> 'topic',
	EVENT_NOTICE	=> 'notice',
	EVENT_NICK	=> 'nick',
	EVENT_QUIT	=> 'quit',
	EVENT_MODE	=> 'mode',
	EVENT_KICK	=> 'kick',
	EVENT_CTCP	=> 'CTCP',
};

use constant DATAGRAM_MAXLEN => 1024;

our $irc;

POE::Session->create(
	package_states => [
		main => [ qw(
			_start
			irc_join
			irc_msg
			irc_public
			irc_part
			irc_topic
			irc_notice
			irc_nick
			irc_quit
			irc_mode
			irc_kick
			irc_ctcp
			irc_raw
			get_datagram
		) ]
	]
);

$poe_kernel->run();

sub _start {
	$irc = POE::Component::IRC::State->spawn(
		Nick	=> IRC_NICKNAME,
		Server	=> IRC_SERVER_HOST,
		Raw	=> 1,
		Password=> IRC_SERVER_PASS,
	);

	$irc->plugin_add('AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new(
		Channels => [ IRC_CHANNELS ]
	));

	$irc->yield(register => qw(
		join
		msg
		public
		part
		topic
		notice
		nick
		quit
		mode
		kick
		ctcp
		raw
	));
	$irc->yield('connect');


	#
	# UDP server
	#

	my $socket = IO::Socket::INET->new(
		Proto		=> 'udp',
		LocalPort	=> UDP_PORT,
	);

	$_[KERNEL]->select_read($socket, "get_datagram");
}

sub log_it {
	my ($chan, $nick, $event, $text) = @_;

	print "Event on channel $chan...\n";
	print "\tuser: $nick\n";
	print "\tevent: $event\n";
	if (defined $text){
		print "\ttext: $text\n";
	}else{
		print "\ttext: NONE\n";
	}

	my $data = {
		when	=> time(),
		chan	=> &escape($chan),
		user	=> &escape($nick),
		event	=> &escape($event),
		text	=> defined $text ? &escape($text) : '',
	};


	my $dbh = DBI->connect(DB_DSN, DB_USER, DB_PASS);

	$dbh->do("INSERT INTO events (`when`, chan, user, event, text) VALUES (?,?,?,?,?)", undef, $data->{when}, $data->{chan}, $data->{user}, $data->{event}, $data->{text});

	$dbh->disconnect();
}

sub escape {
	$_[0] =~ s!([\\"'])!\\$1!g;
	return $_[0];
}

sub irc_join {
	my $nick = (split /!/, $_[ARG0])[0];
	my $chan = $_[ARG1];
	my $irc = $_[SENDER]->get_heap();

	if ($nick eq $irc->nick_name()) {
		print "Starting logging in $chan\n";
		$irc->yield(privmsg => $chan, "Now logging in $chan");
	}else{
		&log_it($chan, $nick, EVENT_JOIN);
	}
}

sub irc_part {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1];
	my $text = $_[ARG2];

	&log_it($chan, $nick, EVENT_PART, $text);
}

sub irc_msg {
}

sub irc_public {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1]->[0];
	my $text = $_[ARG2];

	&log_it($chan, $nick, EVENT_TEXT, $text);
}

sub irc_topic {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1];
	my $text = $_[ARG2];

	&log_it($chan, $nick, EVENT_TOPIC, $text);
}

sub irc_notice {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1]->[0];
	my $text = $_[ARG2];

	&log_it($chan, $nick, EVENT_NOTICE, $text);
}

sub irc_nick {
	my $nick = parse_user($_[ARG0]);
	my $chan = 'all';
	my $text = $_[ARG1];

	&log_it($chan, $nick, EVENT_NICK, $text);
}

sub irc_quit {
	my $nick = parse_user($_[ARG0]);
	my $chan = 'all';
	my $text = $_[ARG1];

	&log_it($chan, $nick, EVENT_QUIT, $text);
}

sub irc_mode {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1];
	my $text = $_[ARG2]; # plus more args

	&log_it($chan, $nick, EVENT_MODE, $text);
}

sub irc_kick {
	my $nick = parse_user($_[ARG0]);
	my $chan = $_[ARG1]->[0];
	my $text = $_[ARG2];

	$text .= " ".$_[ARG3] if defined $_[ARG3];

	&log_it($chan, $nick, EVENT_KICK, $text);
}

sub irc_ctcp {
	my $type = $_[ARG0];
	my $nick = parse_user($_[ARG1]);
	my $chan = $_[ARG2]->[0];
	my $msg = $_[ARG3];

	&log_it($chan, $nick, EVENT_CTCP, $type.' '.$msg);
}

sub irc_raw {
	#print "RAW: $_[ARG0]\n";
}

sub get_datagram {
	my ( $kernel, $socket ) = @_[ KERNEL, ARG0 ];

	my $remote_address = recv( $socket, my $message = "", DATAGRAM_MAXLEN, 0 );
	return unless defined $remote_address;

	my ( $peer_port, $peer_addr ) = unpack_sockaddr_in($remote_address);
	my $human_addr = inet_ntoa($peer_addr);
	print "(server) $human_addr : $peer_port sent us: $message\n";

	if ($message =~ /^(#\S+)\s(.*)$/i){
		print "\tfound channel prefix => $1\n";
		my $chans = $1;
		my $msg = $2;
		my @chans = split /,/, $chans;
		for my $chan(@chans){
			print "\tsending to $chan :: $msg\n";
			$irc->yield(privmsg => $chan, $msg);
			&log_it($chan, 'logbot', EVENT_TEXT, $msg);
		}
	}else{
		my $chan = DEFAULT_CHANNEL;
		print "\tsending to $chan :: $message\n";
		$irc->yield(privmsg => $chan, $message);
		&log_it($chan, 'logbot', EVENT_TEXT, $message);
	}
}


1;

