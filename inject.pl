#!/usr/bin/perl

use strict;
use warnings;

use IO::Socket;
use Data::Dumper;

my $message = $ARGV[0];

while (length $message > 1000){
	my $temp = substr $message, 0, 1000;
	$message = substr $message, 1000;
	&log_value('localhost', 8675, $temp);
}
&log_value('localhost', 8675, $message);

sub log_value {
	my ($server, $port, $value) = @_;

	my $sock = new IO::Socket::INET(
			PeerAddr	=> $server,
			PeerPort	=> $port,
			Proto		=> 'udp',
		) or die('Could not connect: $!');

	print $sock "$value";

	close $sock;
}

