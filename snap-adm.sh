#!/bin/bash
#
# snap-adm.sh - A wicked method of using LVM snapshots for clean tests
#
# The goal of this script is to be able to easily revert back to a
# pristine system state for running fresh development deployments in an
# environment where there is limited console access and no other quick
# provisioning process is feasible.
# 
# USAGE:
#
# /sbin/snap-adm.sh COMMAND
#
# COMMANDS:
#
#   init
#           Initialize the boot loader (initrd image), control
#           LV and configuration file. This MUST be run after 
#           copying this script to a fresh system.
#
#   enable
#
#           Enables the snapshot mirroring to be done on next boot
#
#   disable
#
#           Disables the snapshot mirroring so it will not be done
#           at next boot. If snapshots are currently enabled, they
#           will be deleted at next reboot and the original LVs
#           will be used.
#
#   cleanup
#
#           Remove snapshot LVs. Note: this only works if they have
#           the suffix '_snapshot' and the original LVs exist, which
#           happens after using the 'disable' command and re-booting.
#
#   ignore
#
#           At reboot, ignore all snap-saver actions and leave
#           everything as-is. [Default]
#
#   refresh
#
#           Toggle 'refresh' configuration stanza so that existing
#           snapshots will be discarded at system boot. [Default]
#
#   norefresh
#
#           Toggle 'refresh' configuration stanza so that existing
#           snapshots will NOT be discarded at system boot. On boot,
#           the toggle will automatically be reset to 'refresh'.
#
#   start
#
#           Run by the boot-snap-server.sh during system init to create
#           the snapshot LVs and rename the original LVs so the system
#           mounts the snapshots. This should NOT be run when the final
#           filesystems are mounted.
#
#   status
#
#           Show status of snapshots


# Add some stuff to path, just in case
PATH="$PATH:/sbin:/bin:/usr/bin"

snap_saver_lv=rootvg/snap_saver_lv
snap_saver_mt=/snap-saver
snap_saver_rc=${snap_saver_mt}/snap-saver.rc

snap_saver_enabled_file=${snap_saver_mt}/snap-saver-enabled
snap_saver_disabled_file=${snap_saver_mt}/snap-saver-disabled
snap_saver_norefresh_file=${snap_saver_mt}/snap-saver-norefresh

vg_name=rootvg
enabled_lv=snap_saver_enabled_lv
norefresh_lv=snap_saver_norefresh_lv

if [ "$EUID" = "0" ]; then
    SUDO=
else
    SUDO=/usr/bin/sudo
fi

cmd="$1"

die() {
    echo $* 1>&2
    exit 1
}

mount_cfg() {
    if [ ! -d "$snap_saver_mt" ]; then
        $SUDO mkdir -p "$snap_saver_mt" || die "Error creating dir $snap_saver_mt"
    fi
    if mount | grep -q " on $snap_saver_mt "; then
        true    # no-op
        # echo "$snap_saver_mt already mounted" 1>&2
    else
        $SUDO mount -t ext3 /dev/$snap_saver_lv $snap_saver_mt \
            || eie "Error mounting /dev/$snap_saver_lv"
    fi
}

umount_cfg() {
    $SUDO umount $snap_saver_mt \
        || die "Error un-mounting $snap_saver_mt"
}

do_init() {
        if $SUDO lvdisplay $snap_saver_lv >/dev/null 2>&1 ; then
            echo "$0: LV $snap_saver_lv exists"
        else
            echo "$0: creating LV $snap_saver_lv..."
            vg_name=`echo $snap_saver_lv | awk -F/ '{print $1}'`
            lv_name=`echo $snap_saver_lv | awk -F/ '{print $2}'`

            $SUDO lvcreate --size 1M -n $lv_name $vg_name \
                || die "Error creating LV $lv_name in VG $vg_name"
            $SUDO mkfs.ext3 -m 0 /dev/$vg_name/$lv_name
        fi
        mount_cfg
        if [ ! -f $snap_saver_rc ]; then
            echo "Creating initial $snap_saver_rc" 1>&2
            lvs=`$SUDO lvs --noheadings --separator : -o vg_name,lv_name,lv_size \
                | egrep -v ':[^:]*(swap|snap_saver)[^:]*:' \
                | egrep -v ':[^:]*_(snap|orig)[^:]*:'`
            echo "# $snap_saver_rc" | $SUDO tee $snap_saver_rc >/dev/null
            echo "#" | $SUDO tee -a $snap_saver_rc >/dev/null
            echo "# Configuration for the snap-saver script" \
                | $SUDO tee -a $snap_saver_rc >/dev/null
            echo | $SUDO tee -a $snap_saver_rc >/dev/null
            echo "# snap_saver_lv_list contains the LVs to be handled by snap-saver." \
                | $SUDO tee -a $snap_saver_rc >/dev/null
            echo 'snap_saver_lv_list="\' \
                | $SUDO tee -a $snap_saver_rc >/dev/null
            for i in $lvs; do
                echo "$i \\" | $SUDO tee -a $snap_saver_rc >/dev/null
            done
            echo '"' | $SUDO tee -a $snap_saver_rc >/dev/null

            echo "WARNING -- YOU MUST EDIT $snap_saver_rc !!!" 1>&2
        fi
        
        if [ ! -f $snap_saver_mt/snap-adm.sh ]; then
            echo "copying snap_adm to $snap_saver_mt/ ..."
            $SUDO install $0 $snap_saver_mt/
        fi
        mkdir -p ~/mkinitrd-$$
        (cd /lib/mkinitrd && tar -cf - . | tar xf - -C ~/mkinitrd-$$) || \
            die "Failed to copy /lib/mkinitrd to ~/mkinitrd-$$"
        cp /sbin/boot-snap-saver.sh ~/mkinitrd-$$/boot/80-boot-snap-saver.sh
        $SUDO /sbin/mkinitrd -l ~/mkinitrd-$$
}

set_enable() {
    mount_cfg
    $SUDO rm -f $snap_saver_disabled_file
    $SUDO touch $snap_saver_enabled_file
    echo "snap-saver is ENABLED and will run at next reboot"
}

set_disable() {
    mount_cfg
    $SUDO rm -f $snap_saver_enabled_file
    $SUDO touch $snap_saver_disabled_file
    echo "snap-saver is DISABLED and any snapshots will be removed at next boot"
}

set_ignore() {
    mount_cfg
    $SUDO rm -f $snap_saver_enabled_file $snap_saver_disabled_file
    echo "snap-saver will be IGNORED at next boot"
}

set_refresh() {
    mount_cfg
    $SUDO rm -f $snap_saver_norefresh_file
}

set_norefresh() {
    mount_cfg
    $SUDO touch $snap_saver_norefresh_file
}

stop_snap_saver() {
    echo "Stopping snap-saver (re-activating original LVs)"
    echo "Mounted filesystems:"
    mount
    echo ""
    for entry in `lvs --noheadings --separator : -o lv_name,origin`; do
            lv_name=`echo $entry | awk -F: '{print $1}'`
            lv_orig=`echo $entry | awk -F: '{print $2}'`
            if [ -n "$lv_orig" ]; then
                echo "$lv_name is snapshot of $lv_orig"
                if [[ "$lv_orig" =~ "_orig" ]]; then
                    echo "Snapshot is ACTIVE"
                    if [[ "$lv_name" =~ "_snap" ]]; then
                        echo "ERR - $lv_name already ends with '_snap'"
                    else
                        echo "Renaming $lv_name to ${lv_name}_snap..."
                        lvrename --noudevsync $vg_name/$lv_name $vg_name/${lv_name}_snap
                        echo "Renaming $lv_orig to ${lv_name}..."
                        lvrename --noudevsync $vg_name/${lv_orig} $vg_name/${lv_name}
                    fi
                else
                    echo "Original LV $lv_orig does not end in '_orig'"
                fi
            fi
    done
}

do_cleanup() {
    # Here's the logic:
    #
    # For each entry in the LV list that was configured, 
    # 
    # If both <lv_name> and <lv_name>_snap exist, delete
    # the <lv_name>_snap since it should be the snapshot LV.

    local vg_name lv_name lv_size lv_dev 

    mount_cfg
    . "$snap_saver_rc"
    echo "DEBUG: snap_saver_lv_list=$snap_saver_lv_list"
    for lv_entry in $snap_saver_lv_list; do
        # vars
        vg_name=`echo $lv_entry | awk -F: '{print $1}'`
        lv_name=`echo $lv_entry | awk -F: '{print $2}'`
        lv_size=`echo $lv_entry | awk -F: '{print $3}'`
        #lv_dev=/dev/$vg_name/$lv_name

        if $SUDO lvdisplay $vg_name/${lv_name}_snap >/dev/null 2>&1; then
            echo "$0 - found snapshot volume ${lv_name}_snap" 1>&2
            if $SUDO lvdisplay $vg_name/${lv_name} >/dev/null 2>&1; then
                echo "$0 - removing ${lv_name}_snap..." 1>&2
                $SUDO lvremove -f $vg_name/${lv_name}_snap
            else
                echo "ERR - original LV of ${lv_name}_snap not found - skip" 1>&2
            fi
        else
            "$0 - no snapshot found for $vg_name/$lv_name"
        fi
    done
}

start_snap_saver() {
    local vg_name lv_name lv_size lv_dev 

    for lv_entry in $snap_saver_lv_list; do
        # vars
        vg_name=`echo $lv_entry | awk -F: '{print $1}'`
        lv_name=`echo $lv_entry | awk -F: '{print $2}'`
        lv_size=`echo $lv_entry | awk -F: '{print $3}'`
        lv_dev=/dev/$vg_name/$lv_name

        # Here's the logic:
        # 0.    <lv_name>_snap exists
        #
        #       The <lv_name>_snap is the snapshot of <lv_name>. Most
        #       likely, the system was booted with the snapshot volume
        #       named <lv_name> and then in the init scripts, the
        #       LV was renamed to <lv_name>_snap and <lv_name>_orig
        #       was renamed back to <lv_name>. In this case, we just
        #       remove the <lv_name>_snap and fall through to the 
        #       other tests.
        #
        # 1.    <lv_name> and <lv_name>_orig exist
        #
        #       The <lv_name> is the previous snapshot used on the
        #       last boot. This will be removed and a new snapshot
        #       from <lv_name>_orig will be made.
        #
        # 2.    <lv_name> exists, but <lv_name>_orig doesn't
        #
        #       The system is in the pristine LV configuration. 
        #       This will be re-named to <lv_name>_orig and a new
        #       snapshot from <lv_name>_orig will be made.
        #
        # 3.    <lv_name>_orig exists, but <lv_name> doesn't
        #
        #       This *shouldn't* be the condition at boot, but
        #       is the resulting intermediate state after first
        #       handling the first two.
        #
        # 4.    Any other scenario is "unexpected/unsupported". This
        #       LV will be skipped.

        if lvdisplay $vg_name/${lv_name}_snap >/dev/null 2>&1; then
            echo "$0 - Purging unneeded snapshot volume" 1>&2
            # Scenario 0
            lvremove -f $vg_name/${lv_name}_snap
        fi

        if lvdisplay $vg_name/${lv_name} >/dev/null 2>&1; then
            echo "$0 - LV $vg_name/$lv_name exists" 1>&2
            if lvdisplay $vg_name/${lv_name}_orig >/dev/null 2>&1; then
               echo "$0 - LV $vg_name/${lv_name}_orig exists" 1>&2
               echo "     removing LV $vg_name/${lv_name}" 1>&2
                # Scenario 1
                lvremove -f $vg_name/$lv_name
            else
               echo "$0 - LV $vg_name/${lv_name}_orig doesn't exist" 1>&2
               echo "     renaming LV ${lv_name} -> ${lv_name}_orig" 1>&2
                # Scenario 2
                lvrename $vg_name/$lv_name $vg_name/${lv_name}_orig
            fi
        fi

        # At this point, if <lv_name>_orig exists, we are either half-way
        # through the first two scenarios or we are in scenario 3.
        if lvdisplay $vg_name/${lv_name}_orig >/dev/null 2>&1; then
            echo "$0 - LV $vg_name/${lv_name}_orig exists" 1>&2
            echo "     creating LV $vg_name/${lv_name}_orig" 1>&2
            lvcreate --size $lv_size -s -n $lv_name $vg_name/${lv_name}_orig
            echo "$0 - done with LV $vg_name/$lv_name" 1>&2
        else
            echo "$0 - unknown error with LV $vg_name/$lv_name" 1>&2
        fi
    done

    unset vg_name lv_name lv_size lv_dev 

    return 0
}

do_start() {
    # Note: If we get here, /snap_saver is already mounted

    if grep -q ' / ' /etc/mtab; then
        echo "$0 - 'start' may only be run at system boot" 1>&2
        exit 1
    fi

    if [ -f "$snap_saver_enabled_file" ]; then
        echo "$0 - ENABLED" 1>&2
        if [ -f "$snap_saver_norefresh_file" ]; then
            rm -f "$snap_saver_norefresh_file"
        else
            . "$snap_saver_rc"
            start_snap_saver
        fi
    else
        if [ -f "$snap_saver_disabled_file" ]; then
            stop_snap_saver
        else
            echo "$0 - NOT ENABLED" 1>&2
        fi

    fi
}


do_status() {
    mount_cfg
    if [ -f "$snap_saver_enabled_file" ]; then
        echo "$0 - ENABLED"
        if [ -f "$snap_saver_norefresh_file" ]; then
            echo "$0 - NO REFRESH ($snap_saver_norefresh_file exists)"
        else
            echo "$0 - REFRESH ($snap_saver_norefresh_file does not exist)"
        fi
   else
        echo "$0 - NOT ENABLED"
   fi
   for entry in `$SUDO lvs --noheadings --separator : -o lv_name,origin`; do
        lv_name=`echo $entry | awk -F: '{print $1}'`
        lv_orig=`echo $entry | awk -F: '{print $2}'`
        if [ -n "$lv_orig" ]; then
            echo "$lv_name is snapshot of $lv_orig"
        fi
    done
}

case "$1" in
    init)
        do_init
        ;;
    enable)
        set_enable
        ;;
    disable)
        set_disable
        ;;
    ignore)
        set_ignore
        ;;
    refresh)
        set_refresh
        ;;
    norefresh)
        set_norefresh
        ;;
    cleanup)
        do_cleanup
        ;;
    start)
        do_start
        ;;
    *)  # Status, default
        do_status
        ;;
esac



