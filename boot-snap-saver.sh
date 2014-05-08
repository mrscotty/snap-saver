#!/bin/bash
#
#%stage: filesystem
#%depends: resume
#
# Note: the 'programs' attribute must contain *all* commands needed by snap-adm.sh
#
# Note 2: *never* call 'exit' in this script!!! It will cause a kernel panic!!!
#
#%programs: /sbin/lvdisplay /sbin/lvremove /sbin/lvcreate /sbin/lvrename /sbin/lvscan /sbin/lvs /bin/mount /bin/umount /usr/bin/awk /bin/test /bin/ls
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
## 
#


# CONFIG VARS
snap_saver_lv=rootvg/snap_saver_lv
snap_saver_mt=/snap-saver
snap_saver_sh=/snap-saver/snap-adm.sh

# die "message text"
# IMPORTANT: don't use 'exit' or you'll get a kernel panic!!!
die() {
    echo $* 1>&2
    return 1
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
        ls -latr $snap_saver_mt
        if test -x "$snap_saver_sh" ; then
            echo "found $snap_saver_sh - executing it"
            $snap_saver_sh start
        else
            echo "missing $snap_saver_sh"
            die "$snap_saver_sh does not exist or is not executable"
        fi

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
ret=$?

bar

return $ret

