#!/usr/bin/make -f
#
# This is a 'helper' Makefile for testing the snap-saver scripts
# with Vagrant. You'll need a plain vagrant image (e.g.: our
# SLES-11-SP3 image) provisioned to have perl-Error and git-core
# installed. Put this makefile in the same directory as your Vagrantfile.
#
# My workflow looks similar to the following:
#
#	# Create the vagrant instance, install the initrd image,
#	# reboot with snap-saver installed (status should then be NOT ENABLED)
#	./vag.mk all vag-restart snap-status
#
#	# Enable snap-saver, reboot, and check status (output shows LVs are
#	# snapshots of original LVs)
#	./vag.mk snap-enable vag-restart
#
#	# Create some demo files 
#	./vag.mk demo demo-status
#
#	# Make sure the demo files disappear after reboot
#	./vag.mk vag-restart demo-status
#
#	# Re-create some demo files 
#	./vag.mk demo demo-status
#
#	# Turn off refresh and make sure demo files persist after reboot
#	./vag.mk snap-norefresh vag-restart demo-status
#
#	# After reboot from no-refresh test, the flag for no-refresh
#	# should automatically be removed and a subsequent reboot 
#	# should cause the demo files to disappear
#	./vag.mk vag-restart demo-status
#
#	# If you need to start over with a new Vagrant instance, just
#	# run the following:
#	./vag.mk destroy clean
#
#

#################################################################
# LOCAL CONFIGURATION
#
# Override these in your own vag-build.mk.local, if necessary
#################################################################

-include vag.mk.local

#################################################################
# VARIABLES (SHOULDN'T NEED MODIFICATIONS)
#################################################################

STATES := .repo.state .install.state .initrd.state
VAG_INSTANCE := default
VAG_INSTANCE_LIST := $(VAG_INSTANCE)
VAG_PROVIDER := virtualbox
SSH_CFGS = $(patsubst %,%.sshcfg,$(VAG_INSTANCE_LIST))
VAG_ID_FILES := $(patsubst %,.vagrant/machines/%/$(VAG_PROVIDER)/id,$(VAG_INSTANCE_LIST))

all: .initrd.state

########################################
# VAGRANT OPERATIONS
########################################

.PRECIOUS: $(VAG_ID_FILES)

# Create the Vagrant instance(s)
.vagrant/machines/%/$(VAG_PROVIDER)/id:
	vagrant up $*

# Create the .sshcfg for each instance
%.sshcfg: .vagrant/machines/%/$(VAG_PROVIDER)/id
	vagrant ssh-config $* > $@.tmp
	mv $@.tmp $@

# convenience target for ssh session to configured instances
ssh-%: $(VAG_DIR)/%.sshcfg
	ssh -F $(VAG_DIR)/$*.sshcfg $*

.PHONY: destroy fdestroy

destroy:
	vagrant destroy

fdestroy:
	vagrant destroy -f

########################################
# PACKAGE BUILD
########################################

.repo.state: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"git clone --single-branch --depth=1 file:///git/snap-saver ~/git/snap-saver"
	touch $@

.install.state: .repo.state
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"cd ~/git/snap-saver && sudo install snap-adm.sh boot-snap-saver.sh /sbin/"
	touch $@

.initrd.state: .install.state
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"/sbin/snap-adm.sh init"
	touch $@

.PHONY: clean realclean vag-restart

clean:
	rm -rf $(STATES) $(SSH_CFGS) 

realclean: $(VAG_INSTANCE).sshcfg 
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"rm -rf ~/git/snap-saver"
	rm -f .repo.state

vag-restart:
	vagrant halt && vagrant up

############################################################
# snap-saver app tests
############################################################

.PHONY: snap-status snap-enable snap-refresh snap-norefresh demo demo-status

snap-status: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"/sbin/snap-adm.sh status"

#snap-init: $(VAG_INSTANCE).sshcfg
#	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
#		"/sbin/snap-adm.sh init"

snap-enable: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"/sbin/snap-adm.sh enable"

snap-refresh: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"/sbin/snap-adm.sh refresh"

snap-norefresh: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"/sbin/snap-adm.sh norefresh"

DEMO_FILES := /root-fs.demo /usr/usr-fs.demo /var/var-fs.demo /home/home-fs.demo

demo: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"sudo touch $(DEMO_FILES)"

demo-status: $(VAG_INSTANCE).sshcfg
	-ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) \
		"ls -l $(DEMO_FILES)"


########################################
# DEBUGGING STUFF
########################################

.PHONY: git-status

git-status: $(VAG_INSTANCE).sshcfg
	ssh -F $(VAG_INSTANCE).sshcfg $(VAG_INSTANCE) "cd ~/git/snap-saver && git status"

