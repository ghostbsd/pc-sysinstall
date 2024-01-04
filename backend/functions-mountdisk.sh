#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright (c) 2010 iXsystems, Inc.  All rights reserved.
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

# Functions related mounting the newly formatted disk partitions

# Mounts all the specified partition to the mount-point
mount_partition()
{
  if [ -z "${1}" -o -z "${2}" -o -z "${3}" ]
  then
    exit_err "ERROR: Missing arguments for mount_partition"
  fi

  PART="${1}"
  PARTFS="${2}"
  MNTPOINT="${3}"
  MNTFLAGS="${4}"

  # Setup the MNTOPTS
  if [ -z "${MNTOPTS}" ]
  then
    MNTFLAGS="-o rw"
  else
    MNTFLAGS="-o rw,${MNTFLAGS}"
  fi


  #We are on ZFS, lets setup this mount-point
  if [ "${PARTFS}" = "ZFS" ] ; then
    ZPOOLNAME=$(get_zpool_name "${PART}")

    echo_log "Creating ZFS datasets.."
    # Check if we have multiple zfs mounts specified
    for ZMNT in `echo ${MNTPOINT} | sed 's|,| |g'`
    do
      # Check for any ZFS specific mount options
      ZMNTOPTS="-o `echo $ZMNT | cut -d '(' -f 2 | cut -d ')' -f 1 | sed 's/|/ -o /g'`"
      if [ "$ZMNTOPTS" = "$ZMNT" ] ; then ZMNTOPTS="" ; fi

      # Reset ZMNT with options removed
      ZMNT="`echo $ZMNT | cut -d '(' -f 1`"

      # First make sure we create the mount point
      if [ ! -d "${FSMNT}${ZMNT}" ] ; then
        mkdir -p ${FSMNT}${ZMNT} >>${LOGOUT} 2>>${LOGOUT}
      fi

      if [ "${ZMNT}" = "/" ] ; then
        # If creating ZFS / dataset, give it name that beadm works with
        echo_log "zfs create -o mountpoint=none -p ${ZPOOLNAME}/ROOT"
        rc_halt "zfs create -o mountpoint=none -p ${ZPOOLNAME}/ROOT"
        echo_log "zfs create -o mountpoint=/ -p ${ZPOOLNAME}/ROOT/${BENAME}"
        rc_halt "zfs create -o mountpoint=/ -p ${ZPOOLNAME}/ROOT/${BENAME}"
        echo_log "Stamping ${ZPOOLNAME}${ZMNT} as bootfs"
        rc_halt "zpool set bootfs=${ZPOOLNAME}/ROOT/${BENAME} ${ZPOOLNAME}"
        echo_log "zfs set canmount=noauto ${ZPOOLNAME}/ROOT/${BENAME}"
        rc_halt "zfs set canmount=noauto ${ZPOOLNAME}/ROOT/${BENAME}"
      else
        # Create the target ZFS dataset now
        echo_log "zfs create ${ZMNTOPTS} -p ${ZPOOLNAME}${ZMNT}"
        rc_halt "zfs create ${ZMNTOPTS} -p ${ZPOOLNAME}${ZMNT}"
      fi

    done # End of adding ZFS mounts
  else
    # If we are not on ZFS, lets do the mount now
    # First make sure we create the mount point
    if [ ! -d "${FSMNT}${MNTPOINT}" ]
    then
      mkdir -p ${FSMNT}${MNTPOINT} >>${LOGOUT} 2>>${LOGOUT}
    fi

    echo_log "mount ${MNTFLAGS} ${PART} -> ${FSMNT}${MNTPOINT}"
    sleep 2
    rc_halt "mount ${MNTFLAGS} ${PART} ${FSMNT}${MNTPOINT}"
  fi

};

# Mounts all the new file systems to prepare for installation
mount_all_filesystems()
{
  # Make sure our mount point exists
  mkdir -p ${FSMNT} >/dev/null 2>/dev/null

  # First lets find and mount the / partition
  #########################################################
  for PART in `ls ${PARTDIR}`
  do
    PARTDEV=`echo $PART | sed 's|-|/|g'`
    PARTFS="`cat ${PARTDIR}/${PART} | cut -d '#' -f 1`"
    if [ ! -e "${PARTDEV}" -a "${PARTFS}" != "ZFS" ]
    then
      exit_err "ERROR: The partition ${PARTDEV} does not exist. Failure in bsdlabel?"
    fi

    PARTMNT="`cat ${PARTDIR}/${PART} | cut -d '#' -f 2`"
    PARTENC="`cat ${PARTDIR}/${PART} | cut -d '#' -f 3`"

    if [ "${PARTENC}" = "ON" ]
    then
      EXT=".eli"
    else
      EXT=""
    fi

    # Check for root partition for mounting, including ZFS "/,/usr" type
    echo "$PARTMNT" | grep "/," >/dev/null
    if [ "$?" = "0" -o "$PARTMNT" = "/" ]
    then
      case ${PARTFS} in
        UFS) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
        UFS+S) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
        UFS+SUJ) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
        UFS+J) mount_partition ${PARTDEV}${EXT}.journal ${PARTFS} ${PARTMNT} "async,noatime" ;;
        ZFS) mount_partition ${PARTDEV} ${PARTFS} ${PARTMNT} ;;
        IMAGE) mount_partition ${PARTDEV} ${PARTFS} ${PARTMNT} ;;
        *) exit_err "ERROR: Got unknown file-system type $PARTFS" ;;
      esac
    fi
  done

  # Now that we've mounted "/" lets do any other remaining mount-points
  ##################################################################
  for PART in `ls ${PARTDIR}`
  do
    PARTDEV=`echo $PART | sed 's|-|/|g'`
    PARTFS="`cat ${PARTDIR}/${PART} | cut -d '#' -f 1`"
    if [ ! -e "${PARTDEV}" -a "${PARTFS}" != "ZFS" ]
    then
      exit_err "ERROR: The partition ${PARTDEV} does not exist. Failure in bsdlabel?"
    fi

    PARTMNT="`cat ${PARTDIR}/${PART} | cut -d '#' -f 2`"
    PARTENC="`cat ${PARTDIR}/${PART} | cut -d '#' -f 3`"

    if [ "${PARTENC}" = "ON" ]
    then
      EXT=".eli"
    else
      EXT=""
    fi

    # Check if we've found "/" again, don't need to mount it twice
    echo "$PARTMNT" | grep "/," >/dev/null
    if [ "$?" != "0" -a "$PARTMNT" != "/" ]
    then
       case ${PARTFS} in
         UFS) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
         UFS+S) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
         UFS+SUJ) mount_partition ${PARTDEV}${EXT} ${PARTFS} ${PARTMNT} "noatime" ;;
         UFS+J) mount_partition ${PARTDEV}${EXT}.journal ${PARTFS} ${PARTMNT} "async,noatime" ;;
         ZFS) mount_partition ${PARTDEV} ${PARTFS} ${PARTMNT} ;;
         SWAP) ;;
         IMAGE)
           if [ ! -d "${PARTMNT}" ]
           then
             mkdir -p "${PARTMNT}"
           fi
           mount_partition ${PARTDEV} ${PARTFS} ${PARTMNT}
           ;;
         *) exit_err "ERROR: Got unknown file-system type $PARTFS" ;;
      esac
    fi
  done
};
