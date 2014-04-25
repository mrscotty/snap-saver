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
#           at next boot. [Default]
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
#   pristine
#
#           Attempt to revert LV names back to pristine state so that
#           the system boots from the original LVs.
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
snap_saver_norefresh_file=${snap_saver_mt}/snap-saver-norefresh

vg_name=rootvg
enabled_lv=snap_saver_enabled_lv
norefresh_lv=snap_saver_norefresh_lv

cmd="$1"

die() {
    echo $* 1>&2
    exit 1
}

mount_cfg() {
    if [ ! -d "$snap_saver_mt" ]; then
        sudo mkdir -p "$snap_saver_mt" || die "Error creating dir $snap_saver_mt"
    fi
    if mount | grep -q " on $snap_saver_mt "; then
        true    # no-op
        # echo "$snap_saver_mt already mounted" 1>&2
    else
        sudo mount -t ext3 /dev/$snap_saver_lv $snap_saver_mt \
            || eie "Error mounting /dev/$snap_saver_lv"
    fi
}

umount_cfg() {
    sudo umount $snap_saver_mt \
        || die "Error un-mounting $snap_saver_mt"
}

do_init() {
        if sudo lvdisplay $snap_saver_lv >/dev/null 2>&1 ; then
            echo "$0: LV $snap_saver_lv exists"
        else
            echo "$0: creating LV $snap_saver_lv..."
            vg_name=`echo $snap_saver_lv | awk -F/ '{print $1}'`
            lv_name=`echo $snap_saver_lv | awk -F/ '{print $2}'`

            sudo lvcreate --size 1M -n $lv_name $vg_name \
                || die "Error creating LV $lv_name in VG $vg_name"
            sudo mkfs.ext3 -m 0 /dev/$vg_name/$lv_name
        fi
        mount_cfg
        if [ ! -f $snap_saver_rc ]; then
            echo "Creating initial $snap_saver_rc" 1>&2
            lvs=`sudo lvs --noheadings --separator : -o vg_name,lv_name,lv_size \
                | egrep -v ':[^:]*(swap|snap_saver)[^:]*:' \
                | egrep -v ':[^:]*_(snap|orig)[^:]*:'`
            echo "# $snap_saver_rc" | sudo tee $snap_saver_rc >/dev/null
            echo "#" | sudo tee -a $snap_saver_rc >/dev/null
            echo "# Configuration for the snap-saver script" \
                | sudo tee -a $snap_saver_rc >/dev/null
            echo | sudo tee -a $snap_saver_rc >/dev/null
            echo "# snap_saver_lv_list contains the LVs to be handled by snap-saver." \
                | sudo tee -a $snap_saver_rc >/dev/null
            echo 'snap_saver_lv_list="\' \
                | sudo tee -a $snap_saver_rc >/dev/null
            for i in $lvs; do
                echo "$i \\" | sudo tee -a $snap_saver_rc >/dev/null
            done
            echo '"' | sudo tee -a $snap_saver_rc >/dev/null

            echo "WARNING -- YOU MUST EDIT $snap_saver_rc !!!" 1>&2
        fi
        
        if [ ! -f $snap_saver_mt/snap-adm.sh ]; then
            echo "copying snap_adm to $snap_saver_mt/ ..."
            sudo install $0 $snap_saver_mt/
        fi
        mkdir -p ~/mkinitrd-$$
        (cd /lib/mkinitrd && tar -cf - . | tar xf - -C ~/mkinitrd-$$) || \
            die "Failed to copy /lib/mkinitrd to ~/mkinitrd-$$"
        cp /sbin/boot-snap-saver.sh ~/mkinitrd-$$/boot/80-boot-snap-saver.sh
        sudo /sbin/mkinitrd -l ~/mkinitrd-$$
}

do_enable() {
    mount_cfg
    sudo touch $snap_saver_enabled_file
    echo "snap-saver is ENABLED and will run at next reboot"
}

do_disable() {
    mount_cfg
    sudo rm -f $snap_saver_enabled_file
}

do_refresh() {
    mount_cfg
    sudo rm -f $snap_saver_norefresh_file
}

do_norefresh() {
    mount_cfg
    sudo touch $snap_saver_norefresh_file
}

do_pristine() {
        for entry in `sudo lvs --noheadings --separator : -o lv_name,origin`; do
            lv_name=`echo $entry | awk -F: '{print $1}'`
            lv_orig=`echo $entry | awk -F: '{print $2}'`
            if [ -n "$lv_orig" ]; then
                echo "$lv_name is snapshot of $lv_orig"
                if [[ "$lv_orig" =~ "_orig" ]]; then
                    echo "Snapshot is ACTIVE"
                    if [[ "$lv_name" =~ "_snap" ]]; then
                        echo "ERR - $lv_name already ends with '_snap'"
                    else
                        sudo lvrename $vg_name/$lv_name $vg_name/${lv_name}_snap
                        sudo lvrename $vg_name/${lv_orig} $vg_name/${lv_name}
                    fi
                else
                    echo "Original LV $lv_orig does not end in '_orig'"
                fi
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
    # If we get here, /snap_saver is already mounted

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
        echo "$0 - NOT ENABLED" 1>&2
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
   for entry in `sudo lvs --noheadings --separator : -o lv_name,origin`; do
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
        do_enable
        ;;
    disable)
        do_disable
        ;;
    refresh)
        do_refresh
        ;;
    norefresh)
        do_norefresh
        ;;
    pristine)
        do_pristine
        ;;
    start)
        do_start
        ;;
    *)  # Status, default
        do_status
        ;;
esac



