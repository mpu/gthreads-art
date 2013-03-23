#
# Highlight C code in <pre> elements
# of a Markdown.pl generated files.
#
use strict;

my $incode;

while (<>) {
	if (/^<pre><code>!(\w*)$/) {
		print "<pre class=\"prettyprint lang-$1\">";
		$incode = 1;
	} elsif (/^<\/code><\/pre>$/ and $incode) {
		$incode = 0;
		print "</pre>\n";
	} else {
		print;
	}
}
