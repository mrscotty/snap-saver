#!/bin/bash
#
#%stage: filesystem
#%depends: resume
#
# Note: the 'programs' attribute must contain *all* commands needed by snap-adm.sh
#
#%programs: /sbin/lvdisplay /sbin/lvremove /sbin/lvcreate /sbin/lvrename /sbin/lvscan /sbin/lvs /bin/mount /bin/umount /usr/bin/awk
#%if: ! "$root_already_mounted"
#%dontshow
#
##### creating LVM snapshots for saving pristine system condition
##
## When all the device drivers and other systems have been successfully
## activated and in case the root filesystem has not been mounted yet,
## this will do it and fsck it if neccessary.
##
## Command line parameters
## -----------------------
##
## ro           mount the root device read-only
## 
#
# In the $snap_saver_lv, there should be the file snap_saver.rc
# that contains the following variable:
#
# snap_saver_lv_list="\
#    rootvg:root_lv:/:2G \
#    rootvg:home_lv:/home:500M \
#    rootvg:usr_lv:/usr:1500M \
#    rootvg:var_lv:/var:500M"
#


# CONFIG VARS
snap_saver_lv=rootvg/snap_saver_lv
snap_saver_mt=/snap_saver
snap_saver_rc=/snap_saver/snap_saver.rc
snap_saver_sh=/snap_saver/snap_saver.sh

snap_saver_enabled_file=${snap_saver_mt}/snap_saver_enabled
snap_saver_norefresh_file=${snap_saver_mt}/snap_saver_norefresh

ls -l /setup/*snap*.sh

# die "message text"
die() {
    echo $* 1>&2
    exit 1
}

# snap_saver_check() - check whether we should run
#
#   return 0 if we should run the snap-saver
#   return 1 if we should *not* run the snap-saver
snap_saver() {
    local rc

    rc=1

    if lvdisplay $snap_saver_lv >/dev/null 2>&1; then
        echo "$0: found $snap_saver_lv" 1>&2
        mkdir -p $snap_saver_mt
        mount -t ext3 "/dev/$snap_saver_lv" "$snap_saver_mt" \
            || die "Error mounting $snap_saver_mt"
        if [ ! -x "$snap_saver_sh" ]; then
            die "$snap_saver_sh does not exist or is not executable"
        fi
        $snap_saver_sh start

        umount $snap_saver_mt
    else
        echo "$0: no $snap_saver_lv LV found" 1>&2
    fi
}

bar () {
    echo "=========================================================" 1>&2
    echo "=========================================================" 1>&2
}

bar

# And now for the real thing
snap_saver

bar

return 0

