#!/bin/sh
#-
# Copyright (c) 2018 iXsystems, Inc.  All rights reserved.
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
# $FreeBSD: $

# Query mbr partitions label and display them
##############################

. ${PROGDIR}/backend/functions.sh
. ${PROGDIR}/backend/functions-disk.sh


if [ -z "${1}" ]
then
  echo "Error: No partition specified!"
  exit 1
fi

if [ ! -e "/dev/${1}" ]
then
  echo "Error: Partition /dev/${1} does not exist!"
  exit 1
fi


gpart show ${1} >/dev/null 2>/dev/null
if [ "$?" != "0" ] ; then
  # Partitons is not a primary partition
  echo "${1} is not a primary partition"
  exit
fi


SLICE_PART="${1}"
TMPDIR=${TMPDIR:-"/tmp"}

TYPE=`gpart show ${1} | awk '/^=>/ { printf("%s",$5); }'`
echo "${1}-format: $TYPE"

# Set some search flags
PART="0"
EXTENDED="0"
START="0"
SIZEB="0"

# Walk the slice in on-disk order. gpart lists entries sorted by start block,
# so reporting each one as it is read keeps free space in its true position
# between the labels it separates. Front-ends rely on that ordering when they
# merge adjacent free space after a label is deleted.
FREENUM=1
gpart show ${SLICE_PART} | grep -v '^=>' | while read PSTART PSIZE PINDEX PLABEL PREST
do
  # gpart prints a trailing blank line
  if [ -z "${PINDEX}" ] ; then
    continue
  fi

  # A gap rather than a label. Every gap is reported so it keeps its place in
  # the sequence. blocksize is exact; sizemb rounds down and reads 0 for a gap
  # smaller than 2048 blocks.
  if [ "${PINDEX}" = "-" ] ; then
    echo "${SLICE_PART}-freespace${FREENUM}-blockstart: ${PSTART}"
    echo "${SLICE_PART}-freespace${FREENUM}-blocksize: ${PSIZE}"
    echo "${SLICE_PART}-freespace${FREENUM}-sizemb: $(convert_blocks_to_megabyte ${PSIZE})"
    FREENUM=$((FREENUM + 1))
    continue
  fi

  # Labels are lettered from their index: 1 becomes a, 2 becomes b, and so on
  LETTER=`awk -v char=$((96+${PINDEX})) 'BEGIN { printf "%c\n", char; exit }'`
  curpart="${SLICE_PART}${LETTER}"

  echo "${curpart}-sysid: ${PLABEL}"
  echo "${curpart}-label: ${PLABEL}"
  echo "${curpart}-blockstart: ${PSTART}"
  echo "${curpart}-blocksize: ${PSIZE}"

  SIZEMB=$(convert_blocks_to_megabyte ${PSIZE})
  echo "${curpart}-sizemb: ${SIZEMB}"

done


# Now calculate the largest block of free space
FREEB=`gpart show ${SLICE_PART} | grep '\- free\ -' | awk '{print $2}' | sort -g | tail -1`
FREEMB="`expr ${FREEB} / 2048`"
echo "${1}-freemb: $FREEMB"
echo "${1}-freeblocks: $FREEB"

