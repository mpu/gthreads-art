#
# Generate html for annotated
# code listings.
#
use strict;
use IPC::Open2;

sub beg {
}

sub end {
}

sub md {
	open2(my $out, my $in, "perl tools/Markdown.pl");
	print $in shift;
	close $in;
	my $html = join '', <$out>;
	close $out;
	return $html;
}

sub line {
	my $h = shift;
	print "<div class=\"listing\"><div class=\"descr\">";
	print md($h->{'d'});
	print "</div><div class=\"code\">\n<pre><code>";
	print $h->{'c'};
	print "</code></pre>\n</div></div>\n";
	$h->{'c'} = "";
	$h->{'d'} = "";
	$h->{'n'}++;
	print STDERR "[+] Processed fragment $h->{'n'}\n";
}

sub flush {
	my $h = shift;
	if ($h->{'d'} and $h->{'c'}) {
		line($h);
	}
	if ($h->{'r'}) {
		# print STDERR $h->{'r'};
		print md($h->{'r'});
		$h->{'r'} = "";
	}
}

my ($st, %chunk) = 'r';

while (<>) {
	if (/^!code$/) {
		flush(\%chunk);
		beg() if $st eq 'r';
		$st = 'c';
		next;
	} elsif (/^!descr$/) {
		flush(\%chunk);
		beg() if $st eq 'r';
		$st = 'd';
		next;
	} elsif (/^!end$/) {
		flush(\%chunk);
		$st = 'r';
		if ($chunk{'d'} or $chunk{'c'}) {
			print STDERR "Warning, partial chunk!";
		}
		end();
		next;
	}

	if ($st eq 'c') {
		s/&/&amp;/g;
		s/</&lt;/g;
		s/>/&gt;/g;
		s/\t/    /g;
	}

	$chunk{$st} .= $_;	
}

flush(\%chunk);