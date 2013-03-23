MD_FILES = intro.md mach.md code0.md
HTML_FILES = $(patsubst %.md, html/%.html, $(MD_FILES))

BOOTSTRAP_URL = http://twitter.github.com/bootstrap/assets/bootstrap.zip
PRETTYFY_URL = https://google-code-prettify.googlecode.com/files/prettify-small-4-Mar-2013.tar.bz2

all: \
	html/assets/listing.css \
	html/bootstrap \
	html/google-code-prettify \
	$(HTML_FILES)

html/bootstrap: bootstrap.zip
	unzip $^ -d html
	touch $@

html/google-code-prettify: prettify.tar.bz2 extra/prettify.css extra/lang-asm.js
	tar jxf prettify.tar.bz2 -C html
	cp extra/prettify.css html/google-code-prettify
	cp extra/lang-asm.js html/google-code-prettify
	touch $@

bootstrap.zip:
	curl -o $@ $(BOOTSTRAP_URL)

prettify.tar.bz2:
	curl -o $@ $(PRETTYFY_URL)

html/%.html: %.md head.html tail.html
	perl tools/links.pl $< "$(MD_FILES)" head.html > $@
	perl tools/annot.pl $< | perl tools/highlight.pl >> $@
	perl tools/links.pl $< "$(MD_FILES)" tail.html >> $@

html/assets/%: extra/%
	mkdir -p html/assets
	cp $< $@

clean:
	rm -fr html

superclean: clean
	rm -fr bootstrap.zip prettify.tar.bz2

sync:
	rsync -av ./ h:data/gt

.PHONY: all clean superclean sync
