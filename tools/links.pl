#
# Replace PREVLNK and NEXTLNK by valid links
# to the previous and next part of the article.
# Deal with NAVLIST and FILENAME too.
#
use strict;

sub get_title {
	my $art = shift @_;
	return "" if !$art;

	open (my $fh, "<", $art . ".md")
		or die "cannot open $art";

	while (<$fh>) {
		if (/^##\s/) {
			s/^##\s*//;
			close $fh;
			chop;
			return $_;
		}
	}
}

sub get_neighbors {
	my ($cur, @l) = @_;

	my $idx = 0;
	$idx++ until ($cur eq $l[$idx]);

	return ("", $l[$idx+1]) if ($idx == 0);
	return ($l[$idx-1], $l[$idx+1]);
}

sub build_nav {
	my ($cur, @l) = @_;
	my $res;

	for my $art (@l) {
		my $title = get_title($art);
		my $class = " class=\"active\"" if $art eq $cur;
		$res .= "<li$class><a href=\"$art.html\">$title</a></li>\n";
	}
	return $res;
}

my ($cur, $l) = splice @ARGV, 0, 2;
$cur =~ s/\..*$//;
my (@l) = split / /, $l;
s/\..*$// for (@l);

my $nav = build_nav($cur, @l);

my ($prev, $next) = get_neighbors($cur, @l);
my ($prevtitle, $nexttitle) = (get_title($prev), get_title($next));

my $prevlnk = ($prev and "<a href=\"$prev.html\">&lt; $prevtitle</a>");
my $nextlnk = ($next and "<a href=\"$next.html\">$nexttitle &gt;</a>");

while (<>) {
	s/PREVLNK/$prevlnk/;
	s/NEXTLNK/$nextlnk/;
	s/FILENAME/$cur/;
	s/NAVLIST/$nav/;
	print;
}