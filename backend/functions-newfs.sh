#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright (c) 2014 iXsystems, Inc.  All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$

# Functions related to disk operations using newfs

# Features to enable on freshly created ZPOOLS
DEFAULT_ZPOOLFLAGS="async_destroy empty_bpobj filesystem_limits lz4_compress multi_vdev_crash_dump spacemap_histogram extensible_dataset bookmarks enabled_txg"

get_zpool_flags()
{
  ZPOOLFLAGS="-d"
  for i in $DEFAULT_ZPOOLFLAGS
  do
    ZPOOLFLAGS="$ZPOOLFLAGS -o feature@$i=enabled"
  done
}


# Function which performs the ZFS magic
setup_zfs_filesystem()
{
  PART="$1"
  PARTFS="$2"
  PARTMNT="$3"
  EXT="$4"
  PARTGEOM="$5"
  ZPOOLOPTS="$6"
  ROOTSLICE="`echo ${PART} | rev | cut -b 2- | rev`"
  ZPOOLNAME=$(get_zpool_name "${PART}")
  export ZPOOLNAME

  # Sleep a few moments, let the disk catch its breath
  sleep 5
  sync

  # Check if we have multiple zfs mounts specified
  for i in `echo ${PARTMNT} | sed 's|,| |g'`
  do
    # Strip off any ZFS options
    i=`echo $i | cut -d '(' -f 1`

    # Check if we ended up with needing a zfs bootable partition
    if [ "${i}" = "/" -o "${i}" = "/boot" ]
    then
      if [ "$HAVEBOOT" = "YES" ] ; then continue ; fi
      if [ "${PARTGEOM}" = "MBR" ] ; then
        # Lets stamp the proper ZFS boot loader
        echo_log "Setting up ZFS boot loader support"
        rc_halt "dd if=/boot/zfsboot of=${ROOTSLICE} count=1"
        rc_halt "dd if=/boot/zfsboot of=${PART}${EXT} skip=1 seek=1024"
      fi
    fi
  done

  # Get the default zpool flags
  get_zpool_flags

  if [ -n "${ZFSASHIFT}" ] ; then
    # Set specifed ashift size
    sysctl vfs.zfs.min_auto_ashift=${ZFSASHIFT}
  fi

  # Verify this pool isn't already in use
  zpool list | grep -qw "${ZPOOLNAME}"
  if [ $? -eq 0 ] ; then
    exit_err "The poolname: $ZPOOLNAME is already in use locally!"
  fi

  # Verify this pool isn't lingering on another disk
  zpool import | grep -qw "${ZPOOLNAME}"
  if [ $? -eq 0 ] ; then
    # Need to clear out this pool name so we can re-create
    rc_halt "zpool import -f -N ${ZPOOLNAME}"
    rc_halt "zpool destroy -f ${ZPOOLNAME}"
  fi

  if [ -n "${ZPOOLOPTS}" ] ; then
    echo_log "Creating storage pool ${ZPOOLNAME} with $ZPOOLOPTS"
    rc_halt "zpool create -o altroot=${FSMNT} -m none -f ${ZPOOLNAME} ${ZPOOLOPTS}"
  else
    # No zpool options, create pool on single device
    echo_log "Creating storage pool ${ZPOOLNAME} on ${PART}${EXT}"
    rc_halt "zpool create -o altroot=${FSMNT} -m none -f ${ZPOOLNAME} ${PART}${EXT}"
  fi
  return 0

};

# Runs newfs on all the partiions which we've setup with bsdlabel
setup_filesystems()
{

  # Create the keydir
  rm -rf ${GELIKEYDIR} >/dev/null 2>/dev/null
  mkdir ${GELIKEYDIR}

  # Lets go ahead and read through the saved partitions we created, and determine if we need to run
  # newfs on any of them
  for PART in `ls ${PARTDIR}`
  do
    PARTDEV="`echo $PART | sed 's|-|/|g'`"
    PARTFS="`cat ${PARTDIR}/${PART} | cut -d '#' -f 1`"
    PARTMNT="`cat ${PARTDIR}/${PART} | cut -d '#' -f 2`"
    PARTENC="`cat ${PARTDIR}/${PART} | cut -d '#' -f 3`"
    PARTLABEL="`cat ${PARTDIR}/${PART} | cut -d '#' -f 4`"
    PARTGEOM="`cat ${PARTDIR}/${PART} | cut -d '#' -f 5`"
    PARTXTRAOPTS="`cat ${PARTDIR}/${PART} | cut -d '#' -f 6`"
    PARTIMAGE="`cat ${PARTDIR}/${PART} | cut -d '#' -f 7`"

    if [ ! -e "${PARTDEV}" ] ; then
      exit_err "ERROR: The partition ${PARTDEV} does not exist. Failure in bsdlabel?"
    fi

    # Make sure journaling isn't enabled on this device
    if [ -e "${PARTDEV}.journal" ]
    then
      rc_nohalt "gjournal stop -f ${PARTDEV}.journal"
      rc_nohalt "gjournal clear ${PARTDEV}"
    fi

    # Setup encryption if necessary
    if [ "${PARTENC}" = "ON" -a "${PARTFS}" != "SWAP" ]
    then
      echo_log "Creating geli provider for ${PARTDEV}"

      rc_halt "kldstat -v |grep -q g_eli || kldload geom_eli"
      if [ -e "${PARTDIR}-enc/${PART}-encpass" ] ; then
        # Using a passphrase
        rc_halt "geli init -g -b -J ${PARTDIR}-enc/${PART}-encpass ${PARTDEV}"
        rc_halt "geli attach -j ${PARTDIR}-enc/${PART}-encpass ${PARTDEV}"
        touch ${TMPDIR}/.grub-install-geli
      else
        # No Encryption password, use key file
        rc_halt "dd if=/dev/random of=${GELIKEYDIR}/${PART}.key bs=64 count=1"
        rc_halt "geli init -g -b -s 4096 -P -K ${GELIKEYDIR}/${PART}.key ${PARTDEV}"
        rc_halt "geli attach -p -k ${GELIKEYDIR}/${PART}.key ${PARTDEV}"

      fi

      EXT=".eli"
    else
      # No Encryption
      EXT=""
    fi

    # If we are doing mirrored ZFS disks
    if [ -n "$GELI_CLONE_ZFS_DISKS" -a "$GELI_CLONE_ZFS_DEV" = "$PARTDEV" ] ; then
       for gC in $GELI_CLONE_ZFS_DISKS
       do
         echo_log "Setting up GELI on mirrored disks: ${gC}"
         rc_halt "geli init -g -b -J ${PARTDIR}-enc/${PART}-encpass ${gC}"
         rc_halt "geli attach -j ${PARTDIR}-enc/${PART}-encpass ${gC}"
       done
    fi

    case ${PARTFS} in
      UFS)
        echo_log "NEWFS: ${PARTDEV} - ${PARTFS}"
        sleep 2
        rc_halt "newfs -t ${PARTXTRAOPTS} ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "sync"
        rc_halt "glabel label ${PARTLABEL} ${PARTDEV}${EXT}"
        rc_halt "sync"

        # Set flag that we've found a boot partition
        if [ "$PARTMNT" = "/boot" -o "${PARTMNT}" = "/" ] ; then
		  HAVEBOOT="YES"
        fi
        sleep 2
        ;;

      UFS+S)
        echo_log "NEWFS: ${PARTDEV} - ${PARTFS}"
        sleep 2
        rc_halt "newfs -t ${PARTXTRAOPTS} -U ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "sync"
        rc_halt "glabel label ${PARTLABEL} ${PARTDEV}${EXT}"
        rc_halt "sync"
	    # Set flag that we've found a boot partition
	    if [ "$PARTMNT" = "/boot" -o "${PARTMNT}" = "/" ] ; then
          HAVEBOOT="YES"
        fi
        sleep 2
        ;;

      UFS+SUJ)
        echo_log "NEWFS: ${PARTDEV} - ${PARTFS}"
        sleep 2
        rc_halt "newfs -t ${PARTXTRAOPTS} -U ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "sync"
        rc_halt "tunefs -j enable ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "sync"
        rc_halt "glabel label ${PARTLABEL} ${PARTDEV}${EXT}"
        rc_halt "sync"
	    # Set flag that we've found a boot partition
	    if [ "$PARTMNT" = "/boot" -o "${PARTMNT}" = "/" ] ; then
          HAVEBOOT="YES"
        fi
        sleep 2
        ;;


      UFS+J)
        echo_log "NEWFS: ${PARTDEV} - ${PARTFS}"
        sleep 2
        rc_halt "newfs ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "gjournal label -f ${PARTDEV}${EXT}"
        sleep 2
        rc_halt "newfs ${PARTXTRAOPTS} -O 2 -J ${PARTDEV}${EXT}.journal"
        sleep 2
        rc_halt "sync"
        rc_halt "glabel label ${PARTLABEL} ${PARTDEV}${EXT}.journal"
        rc_halt "sync"
	    # Set flag that we've found a boot partition
	    if [ "$PARTMNT" = "/boot" -o "${PARTMNT}" = "/" ] ; then
          HAVEBOOT="YES"
  	    fi
        sleep 2
        ;;

      ZFS)
        echo_log "NEWFS: ${PARTDEV} - ${PARTFS}"
        setup_zfs_filesystem "${PARTDEV}" "${PARTFS}" "${PARTMNT}" "${EXT}" "${PARTGEOM}" "${PARTXTRAOPTS}"
        ;;

      SWAP)
        rc_halt "sync"
	if [ -n "$ZFS_SWAP_DEVS" ] ; then
	  setup_gmirror_swap "$ZFS_SWAP_DEVS"
	  sleep 5
          rc_halt "glabel label ${PARTLABEL} /dev/mirror/swapmirror"
        else
          rc_halt "glabel label ${PARTLABEL} ${PARTDEV}${EXT}"
        fi
        rc_halt "sync"
        sleep 2
        ;;

      IMAGE)
        write_image "${PARTIMAGE}" "${PARTDEV}"
        sleep 2
        ;;

      *) exit_err "ERROR: Got unknown file-system type $PARTFS" ;;
    esac

  done
};


# Takes a list of args to setup as a swapmirror
setup_gmirror_swap()
{
  rc_halt "kldstat -v |grep -q g_mirror || kldload geom_mirror"
  rc_nohalt "gmirror destroy swapmirror"
  rc_halt "gmirror label swapmirror ${@}"
}
