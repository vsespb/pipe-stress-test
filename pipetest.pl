#!/usr/bin/env perl

use strict;
use warnings;
use IO::Pipe;
use Digest::MD5 qw/md5_hex/;



sub sysreadfull($$$)
{
	my ($file, $len) = ($_[0], $_[2]);
	my $n = 0;
	while ($len - $n) {
		my $i = sysread($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			print "$$ sysread returned $i\n";
			if ($i == 0) {
				return $n;
			} else {
				$n += $i;
			}
		} elsif ($!{EINTR}) {
			print "$$ sysread returned EINTR\n";
			redo;
		} else {
			my $errno_i = $!+0;
			my $errno_s = "$!";
			print "$$ sysread returned errno=$errno_i ($errno_s)\n";
			return $n ? $n : undef;
		}
	}
	return $n;
}

sub syswritefull($$)
{
	my ($file, $len) = ($_[0], length($_[1]));
	my $n = 0;
	while ($len - $n) {
		my $i = syswrite($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			print "$$ syswrite returned $i\n";
			$n += $i;
		} elsif ($!{EINTR}) {
			print "$$ syswrite returned EINTR\n";
			redo;
		} else {
			my $errno_i = $!+0;
			my $errno_s = "$!";
			print "$$ syswrite returned errno=$errno_i ($errno_s)\n";
			return $n ? $n : undef;
		}
	}
	return $n;
}


$|=1;

my $filename = $ARGV[0];
open my $fh, "<", $filename or die "Couldn't open file: $!";
binmode $fh or die $!;
my $data;

{
	local $/=undef;
	$data = <$fh>;
};
close $fh or die $!;

print "PARENT PID $$\n";

my $data_len = length($data);
my $data_md5 = md5_hex($data);

print "data length: ".$data_len."\n";
print "data md5: ".$data_md5."\n";


my $ppid = $$;

my $pp = new IO::Pipe;

my $pid = fork();
if ($pid) { # parent
	$|=1;
	$pp->writer();
	$pp->autoflush(1);
	$pp->blocking(1);
	binmode $pp;

	while (1) {
		print "$$ parent - loop begin\n";
		print "$$ parent - syswritefull - writing $data_len bytes\n";
		my $res = syswritefull($pp, $data);
		die if md5_hex($data) ne $data_md5;
		die if $res != $data_len;
		print "$$ parent - syswritefull - wrote $res bytes\n";
		print "$$ parent - loop end\n";
	}

} elsif (defined $pid) { # child
	$|=1;
	print "CHILD PID $$\n";
	$pp->reader();
	$pp->autoflush(1);
	$pp->blocking(1);
	binmode $pp;
	
	while (1) {
		print "$$ child - loop begin\n";
		my $data_child = undef;
		print "$$ child - sysreadfull - reading $data_len bytes\n";
		my $res = sysreadfull($pp, $data_child, $data_len);
		print "$$ child - sysreadfull - read $res bytes\n";
		die if $res != $data_len;

		my $ok = $data_child eq $data;
		print "$$ child - data matches original: ".($ok ? 'YES' : 'NO')."\n";
		die unless $ok;

		my $data_md5_child = md5_hex($data_child);
		my $md5_ok = $data_md5_child eq $data_md5;

		print "$$ child - md5 of received data: ".$data_md5_child." (matches original: ".($md5_ok ? 'YES' : 'NO' ).")\n";
		print "$$ child - loop end\n";
	}
} else {
	die "fork error $!";
}

__END__

