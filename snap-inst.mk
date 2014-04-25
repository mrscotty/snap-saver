#!/usr/bin/make -f
#
# Danger -- here be dragons!!!
#
# This script installs the snap-saver, a wicked hack that makes
# all changes to a system temporary. It creates a snapshot LV
# of the specified LVs and renames the LVs so that the snapshots
# are mounted. Later in the boot process, the LVs are renamed back
# to their original names so that in the event of an unexpected
# reboot, the system boots with the pristine state.
#
# !!! NEVER RUN THIS ON A PROD SYSTEM !!!
# !!!  FOR DEVELOPMENT SYSTEMS ONLY   !!!
#
#
# USAGE:
#
# 	To install on the target DEVELOPMENT system:
#
# 		cd <this directory>
# 		./snap-inst.mk
#

# L_DIR is just a temporary directory for preparing the new initrd
# image.
L_DIR = $(HOME)/lib-mkinitrd

# Default target is to generate new initrd and install
# the snap-adm.sh script.
all: initrd-snap-saver /sbin/snap-adm.sh

$(L_DIR):
	mkdir -p $@
	(cd /lib/mkinitrd && tar -cf - . | tar xf - -C $@)

#$(L_DIR)/boot/80-snap-saver.sh: $(L_DIR)/scripts/snap-saver.sh
#	(cd $(L_DIR)/boot && ln -s -f ../scripts/snap-saver.sh 80-snap-saver.sh)

#$(L_DIR)/boot/80-boot-snap-saver.sh: boot-snap-saver.sh $(L_DIR)
#	install -T $< $@

/sbin/snap-adm.sh: snap-adm.sh
	sudo install -T $< $@

#initrd-snap-saver: $(L_DIR)/boot/80-boot-snap-saver.sh 
#	sudo /sbin/mkinitrd -l $(HOME)/lib-mkinitrd 

DEMO_FILES := /root-fs.demo /usr/usr-fs.demo /var/var-fs.demo /home/home-fs.demo

demo: $(DEMO_FILES)

%.demo:
	echo "Filename: $@" | sudo tee $@.tmp >/dev/null
	sudo mv $@.tmp $@

demo-status:
	@for i in $(DEMO_FILES); do \
		if [ -f $$i ]; then \
			echo "File $$i exists"; \
		fi; \
	done

/dev/rootvg/snap_saver_lv:
	sudo /sbin/lvcreate --size 1M -n snap_saver_lv rootvg
	sudo mkfs.ext3 -m 0 $@

/snap_saver:
	mkdir -p $@



