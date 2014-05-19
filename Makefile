# Makefile for snap-saver
#

# To run the tests with Vagrant, you'll need either a Vagrantfile
# in the current working directory or you'll need to set the
# VAGRANT_CWD to the directory containing your test Vagrantfile.

ifdef VAGRANT_CWD
	SNAP_TARBALL = $(VAGRANT_CWD)/snap-saver.tgz
	VAG_DIR = $(VAGRANT_CWD)
else
	SNAP_TARBALL = snap-saver.tgz
	VAG_DIR = .
endif

VAG_PROVIDER = virtualbox

$(SNAP_TARBALL): snap-adm.sh boot-snap-saver.sh install.sh
	tar -czf $@ $^

.PRECIOUS: $(VAG_DIR)/.vagrant/machines/%/$(VAG_PROVIDER)/id

$(VAG_DIR)/.vagrant/machines/%/$(VAG_PROVIDER)/id:
	cd $(VAG_DIR) && vagrant up $*

%.sshcfg: $(VAG_DIR)/.vagrant/machines/%/$(VAG_PROVIDER)/id
	vagrant ssh-config $* > $@.tmp
	mv $@.tmp $@

test: $(SNAP_TARBALL) default.sshcfg
	prove -Ilib t/*.t

.PHONY: update
update: $(SNAP_TARBALL) default.sshcfg
	ssh -F default.sshcfg default \
		"mkdir -p snap-pkg && cd snap-pkg && \
		tar -xzf /vagrant/snap-saver.tgz && ./install.sh"

clean:
	rm default.sshcfg
