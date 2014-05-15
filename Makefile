# Makefile for snap-saver
#

# To run the tests with Vagrant, you'll need either a Vagrantfile
# in the current working directory or you'll need to set the
# VAGRANT_CWD to the directory containing your test Vagrantfile.

ifdef VAGRANT_CWD
	SNAP_TARBALL = $(VAGRANT_CWD)/snap-saver.tgz
else
	SNAP_TARBALL = snap-saver.tgz
endif

$(SNAP_TARBALL): snap-adm.sh boot-snap-saver.sh install.sh
	tar -czf $@ $^

default.sshcfg:
	vagrant ssh-config default > $@.tmp
	mv $@.tmp $@

test: $(SNAP_TARBALL) default.sshcfg
	prove -Ilib t/*.t
