#!/usr/bin/perl
use warnings;
use strict;
use ExtUtils::MakeMaker;

# Add a few more targets.
sub MY::postamble {
q{
all:: extra_build
clean:: extra_clean
install:: extra_install
pure_install:: extra_install

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

# Parameterized programs used by Makefile.
FIND?=find
SED?=sed

# Additional configurable path variables.
W3M_CGI_BIN?=$(PREFIX)/lib/w3m/cgi-bin
SYSCONFDIR?=/etc/ikiwiki
MANDIR?=$(PREFIX)/share/man

tflag=$(shell if [ -n "$$NOTAINT" ] && [ "$$NOTAINT" != 1 ]; then printf -- "-T"; fi)
extramodules=$(shell if [ "$$PROFILE" = 1 ]; then printf -- "-d:NYTProf"; fi)
outprogs=ikiwiki.out ikiwiki-transition.out ikiwiki-calendar.out ikiwiki-comment.out
scripts=ikiwiki-update-wikilist ikiwiki-makerepo
sysconfdir_scripts=ikiwiki-mass-rebuild ikiwiki-update-wikilist
shebang_scripts=$(shell $(FIND) . -type f \( -name '*.in' -o -name '*.cgi' -o -name '*.pm' -o -name '*.pm.example' -o -name '*.t' -o -name '*.setup' -o -name 'ikiwiki-comment' -o -name 'ikiwiki-mass-rebuild' -o -name 'ikiwiki-update-wikilist' -o -name 'gitremotes' -o -name 'mdwn2man' -o -name 'pm_filter' -o -name 'po2wiki' -o -name 'externaldemo' \))

PROBABLE_INST_LIB=$(shell \\
	if [ "$(INSTALLDIRS)" = "perl" ]; then \\
		echo $(INSTALLPRIVLIB); \\
	elif [ "$(INSTALLDIRS)" = "site" ]; then \\
		echo $(INSTALLSITELIB); \\
	elif [ "$(INSTALLDIRS)" = "vendor" ]; then \\
		echo $(INSTALLVENDORLIB); \\
	fi \\
)

%.out: %.in
	./pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB) < $< > $@
	chmod +x $@

ikiwiki.setup:
	HOME=/home/me $(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in --dumpsetup ikiwiki.setup

extra_build: perl_shebangs $(outprogs) ikiwiki.setup docwiki sysconfdir
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
	./mdwn2man ikiwiki-makerepo 1 doc/ikiwiki-makerepo.mdwn > ikiwiki-makerepo.man
	./mdwn2man ikiwiki-transition 1 doc/ikiwiki-transition.mdwn > ikiwiki-transition.man
	./mdwn2man ikiwiki-update-wikilist 1 doc/ikiwiki-update-wikilist.mdwn > ikiwiki-update-wikilist.man
	./mdwn2man ikiwiki-calendar 1 doc/ikiwiki-calendar.mdwn > ikiwiki-calendar.man
	./mdwn2man ikiwiki-comment 1 doc/ikiwiki-comment.mdwn > ikiwiki-comment.man
	$(MAKE) -C po
	$(PERL) -pi.bkp -e "s/Version:.*/Version: $(VER)/" ikiwiki.spec
	rm -f ikiwiki.spec.bkp
	
docwiki:
	$(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in --setup docwiki.setup --refresh

perl_shebangs: pm_to_blib
ifneq "$(PERL)" "/usr/bin/perl"
	set -e; \
	for file in $(shebang_scripts); do \
		$(PERL) -pe "s|^#!/usr/bin/perl\b|#!$(PERL)| if 1" < $$file > "$$file.new"; \
		[ -x $$file ] && chmod +x "$$file.new"; \
		mv -f "$$file.new" $$file; \
	done
endif

perl_shebangs_clean:
ifneq "$(PERL)" "/usr/bin/perl"
	set -e; \
	for file in $(shebang_scripts); do \
		$(PERL) -pe "s|^#!$(PERL)\b|#!/usr/bin/perl| if 1" < $$file > "$$file.new"; \
		[ -x $$file ] && chmod +x "$$file.new"; \
		mv -f "$$file.new" $$file; \
	done
endif

sysconfdir:
	$(PERL) -pi -e "s|\"/etc/ikiwiki|\"$(SYSCONFDIR)|g" $(sysconfdir_scripts)
	
extra_clean: perl_shebangs_clean
	$(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in --setup docwiki.setup --clean
	rm -f *.man $(outprogs) ikiwiki.setup plugins/*.pyc
	rm -fr t/tmp t/manual/*/git/ t/manual/*/html/ t/tinyblog/.ikiwiki/ t/tinypodcast/.ikiwiki/
	$(MAKE) -C po clean

reset-generated:
	git checkout po ikiwiki.spec

# Joey uses this before committing.
myclean: clean reset-generated

underlay_install:
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki
	set -e; \
	for dir in `$(FIND) underlays -follow -mindepth 1 -type d | $(SED) -e 's|^underlays/||'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `$(FIND) underlays/$$dir -follow -maxdepth 1 -type f ! -name jquery.js ! -name jquery-ui.css ! -name jquery-ui.js ! -name jquery.tmpl.js`; do \
			if ! cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir 2>/dev/null; then \
				install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
			fi; \
		done; \
	done

	# The directive docs become their own special underlay.
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive
	set -e; \
	for file in doc/ikiwiki/directive/*; do \
		if [ -f "$$file" ]; then \
			if ! cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive 2>/dev/null; then \
				install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive; \
			fi; \
		fi \
	done

	# Themes have their base.css (if present) and then
	# style.css appended to the normal one.
	set -e; \
	for theme in themes/*; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$theme; \
		for file in $$theme/*; do \
			if echo "$$file" | grep -q style.css; then \
				(cat doc/style.css; cat $$theme/base.css 2>/dev/null || :; cat $$file) > $(DESTDIR)$(PREFIX)/share/ikiwiki/$$theme/style.css; \
			elif echo "$$file" | grep -q base.css; then \
				:; \
			elif [ -f "$$file" ]; then \
				if ! cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$file 2>/dev/null; then \
					install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$file; \
				fi; \
			fi \
		done; \
	done

extra_install: underlay_install
	# Install example sites.
	set -e; \
	for dir in `$(FIND) doc/examples -type d ! -regex '.*discussion.*' | $(SED) -ne 's|^doc/examples/||p'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$dir; \
	done
	set -e; \
	for file in `$(FIND) doc/examples -type f ! -regex '.*discussion.*' | $(SED) -ne 's|^doc/examples/||p'`; do \
		if ! cp -pRL doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file 2>/dev/null; then \
			install -m 644 doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file; \
		fi; \
	done

	set -e; \
	for dir in `$(FIND) templates -follow -type d`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `$(FIND) $$dir -follow -maxdepth 1 -type f`; do \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		done; \
	done
	
	install -d $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins
	set -e; \
	for file in `$(FIND) plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* -name \*.py`; do \
		install -m 644 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done
	set -e; \
	for file in `$(FIND) plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* ! -name \*.py ! -name \*.pyc`; do \
		install -m 755 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done

	install -d $(DESTDIR)$(MANDIR)/man1
	install -m 644 ikiwiki.man $(DESTDIR)$(MANDIR)/man1/ikiwiki.1
	install -m 644 ikiwiki-makerepo.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-makerepo.1
	install -m 644 ikiwiki-transition.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-transition.1
	install -m 644 ikiwiki-update-wikilist.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-update-wikilist.1
	install -m 644 ikiwiki-calendar.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-calendar.1
	install -m 644 ikiwiki-comment.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-comment.1
	
	install -d $(DESTDIR)$(MANDIR)/man8
	install -m 644 ikiwiki-mass-rebuild.man $(DESTDIR)$(MANDIR)/man8/ikiwiki-mass-rebuild.8
	
	install -d $(DESTDIR)$(PREFIX)/sbin
	install ikiwiki-mass-rebuild $(DESTDIR)$(PREFIX)/sbin

	install -d $(DESTDIR)$(W3M_CGI_BIN)
	install ikiwiki-w3m.cgi $(DESTDIR)$(W3M_CGI_BIN)

	install -d $(DESTDIR)$(PREFIX)/bin
	set -e; \
	for prog in $(outprogs) $(scripts); do \
		install $$prog $(DESTDIR)$(PREFIX)/bin/$$(echo $$prog | $(SED) 's/\.out//'); \
	done

	$(MAKE) -C po install DESTDIR=$(DESTDIR) PREFIX=$(PREFIX)
	
	# These might fail if a regular user is installing into a home
	# directory.
	-install -d $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 wikilist $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 auto.setup $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 auto-blog.setup $(DESTDIR)$(SYSCONFDIR)

# The git/hg plugins want to chdir; so does Devel::Cover. Skip those tests
# to stop them hurting each other.
coverage:
	cover -delete
	$(MAKE) test PERL5OPT=-MDevel::Cover PERL5LIB=. TEST_FILES="$(filter-out t/git.t t/mercurial.t,$(wildcard t/*.t))"
	cover

git-dist:
	git archive --format=tar --prefix=IkiWiki-$(VER)/ HEAD | xz -c > IkiWiki-$(VER).tar.xz
}
}

WriteMakefile(
	NAME		=> 'IkiWiki',
	PREFIX		=> "/usr/local",
	PM_FILTER	=> './pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB)',
	MAN1PODS	=> {},
	PREREQ_PM	=> {
		'XML::Simple'		=> "0",
		'Text::Markdown'	=> "0",
		'Date::Manip'		=> "0",
		'Date::Parse'		=> "0",
		'HTML::Template'	=> "0",
		'HTML::Scrubber'	=> "0",
		'CGI::FormBuilder'	=> "3.02.02",
		'CGI::Session'		=> "0",
		'Mail::Sendmail'	=> "0",
		'HTML::Parser'		=> "0",
		'URI'			=> "0",
		'Data::Dumper'		=> "2.11",
		'YAML::XS'		=> "0",
	},
);
