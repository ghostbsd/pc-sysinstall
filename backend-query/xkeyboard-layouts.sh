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

FOUND="0"
TMPLIST="/tmp/.xkeyList.$$"
XLST="/usr/local/share/X11/xkb/rules/xorg.lst"

if [ ! -e "${XLST}" ] ; then
  exit 1
fi

# Lets parse the xorg.list file, and see what layouts are supported
while read line
do

  if [ "$FOUND" = "1" -a ! -z "$line" ]
  then
    echo $line | grep '! ' >/dev/null 2>/dev/null
    if [ "$?" = "0" ]
    then
      break
    else 
      echo "$line" >> ${TMPLIST}
    fi 
  fi 

  if [ "${FOUND}" = "0" ]
  then
    echo $line | grep '! layout' >/dev/null 2>/dev/null
    if [ "$?" = "0" ]
    then
      FOUND="1"
    fi 
  fi

done < $XLST

sort -b -d +1 $TMPLIST

# Delete the tmp file
rm $TMPLIST

exit 0
