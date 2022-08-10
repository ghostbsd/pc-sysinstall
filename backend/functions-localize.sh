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

# Functions which runs commands on the system

. ${BACKEND}/functions.sh
. ${BACKEND}/functions-parse.sh


# Function which localizes a FreeBSD install
localize_freebsd()
{
  sed -i '' "s/lang=C/lang=${LOCALE}/g" ${FSMNT}/etc/login.conf
  sed -i '' "s/en_US/${LOCALE}/g" ${FSMNT}/etc/profile
  sed -i '' "s/en_US/${LOCALE}/g" ${FSMNT}/usr/share/skel/dot.profile
};

localize_x_desktops() {

  # Check for and customize GNOME / GDM lang
  ##########################################################################

  # See if GDM is enabled and customize its lang
  if [ -d "${FSMNT}/usr/local/etc/gdm" ] ; then
    echo "LANG=\"${LOCALE}.UTF-8\"" > ${FSMNT}/usr/local/etc/gdm/locale.conf
    echo "LC_CTYPE=\"${LOCALE}.UTF-8\"" >> ${FSMNT}/usr/local/etc/gdm/locale.conf
    echo "LC_MESSAGES=\"${LOCALE}.UTF-8\"" >> ${FSMNT}/usr/local/etc/gdm/locale.conf
  fi
  cat ${FSMNT}/etc/rc.conf 2>/dev/null | grep -q "gdm_enable=\"YES\"" 2>/dev/null
  if [ "$?" = "0" ] ; then
    echo "gdm_lang=\"${LOCALE}.UTF-8\"" >> ${FSMNT}/etc/rc.conf
  fi


  if [ -d "${FSMNT}/usr/local/etc/lightdm" ] ; then
    if [ -f "${FSMNT}/usr/local/share/xgreeters/slick-greeter.desktop" ] ; then
      sed -i '' "s/Exec=slick-greeter/Exec=env LANG=${LOCALE}.UTF-8 slick-greeter/g" ${FSMNT}/usr/local/share/xgreeters/slick-greeter.desktop
    elif [ -f "${FSMNT}/usr/local/share/xgreeters/lightdm-gtk-greeter.desktop" ] ; then
      sed -i '' "s/Exec=lightdm-gtk-greeter/Exec=env LANG=${LOCALE}.UTF-8 lightdm-gtk-greeter/g" ${FSMNT}/usr/local/share/xgreeters/lightdm-gtk-greeter.desktop
    fi
  fi

};

# Function which localizes a TrueOS install
localize_pcbsd()
{
  # Check if we have a localized splash screen and copy it
  if [ -e "${FSMNT}/usr/local/share/pcbsd/splash-screens/loading-screen-${SETLANG}.pcx" ]
  then
    cp ${FSMNT}/usr/local/share/pcbsd/splash-screens/loading-screen-${SETLANG}.pcx ${FSMNT}/boot/loading-screen.pcx
  fi

};

localize_x_keyboard()
{
  KEYMOD="$1"
  KEYLAY="$2"
  KEYVAR="$3"
  OPTION="grp\\tgrp:alt_shift_toggle"

  if [ "${KEYMOD}" != "NONE" ] ; then
    SETXKBMAP="-model ${KEYMOD}"
    KXMODEL="${KEYMOD}"
  else
    KXMODEL="pc104"
  fi

  if [ "${KEYLAY}" != "NONE" ] ; then
    localize_key_layout "$KEYLAY"
    SETXKBMAP="${SETXKBMAP} -layout ${KEYLAY}"
    KXLAYOUT="${KEYLAY}"
  else
    KXLAYOUT="us"
  fi

  if [ "${KEYVAR}" != "NONE" ] ; then
    SETXKBMAP="${SETXKBMAP} -variant ${KEYVAR}"
  fi

  # Setup .xprofile with our setxkbmap call now
  if [ ! -z "${SETXKBMAP}" ] ; then
    if [ ! -e "${FSMNT}/usr/share/skel/.xprofile" ]
    then
      echo "#!/bin/sh" > ${FSMNT}/usr/share/skel/.xprofile
    fi

    # Save the keyboard layout for user / root X logins
    echo "setxkbmap ${SETXKBMAP}" >>${FSMNT}/usr/share/skel/.xprofile
    chmod 755 ${FSMNT}/usr/share/skel/.xprofile
    cp ${FSMNT}/usr/share/skel/.xprofile ${FSMNT}/root/.xprofile

    # Save it for lightdm
    if [ -f ${FSMNT}/usr/local/etc/lightdm/lightdm.conf ] ; then
      sed -i '' "s/#greeter-setup-script=/greeter-setup-script=setxkbmap ${SETXKBMAP}/g" ${FSMNT}/usr/local/etc/lightdm/lightdm.conf
    fi
  fi

  # For Mate and XFCE
  if [ "${KEYVAR}" == "NONE" ] ; then
    if [ -f ${FSMNT}/usr/local/share/glib-2.0/schemas/org.mate.peripherals-keyboard-xkb.gschema.xml ] ; then
      keyboard_xkb=${FSMNT}/usr/local/share/glib-2.0/schemas/92_org.mate.peripherals-keyboard-xkb.kbd.gschema.override
      echo "[org.mate.peripherals-keyboard-xkb.kbd]" > ${keyboard_xkb}
      echo "layouts=['${KXLAYOUT}']" >> ${keyboard_xkb}
      echo "model='${KXMODEL}'" >> ${keyboard_xkb}
      echo "options=['${OPTION}']" >> ${keyboard_xkb}
      run_chroot_cmd "glib-compile-schemas /usr/local/share/glib-2.0/schemas/"
    elif [ -f ${FSMNT}/usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml ] ; then
      sed -i '' "s/value="\""us"\""/value="\""${KXLAYOUT}"\""/g" ${FSMNT}/usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml
    fi
  else
    if [ -f ${FSMNT}/usr/local/share/glib-2.0/schemas/org.mate.peripherals-keyboard-xkb.gschema.xml ] ; then
      keyboard_xkb=${FSMNT}/usr/local/share/glib-2.0/schemas/92_org.mate.peripherals-keyboard-xkb.kbd.gschema.override
      echo "[org.mate.peripherals-keyboard-xkb.kbd]" > ${keyboard_xkb}
      echo "layouts=['${KXLAYOUT}\\t${KEYVAR}']" >> ${keyboard_xkb}
      echo "model='${KXMODEL}'" >> ${keyboard_xkb}
      echo "options=['${OPTION}']" >> ${keyboard_xkb}
      run_chroot_cmd "glib-compile-schemas /usr/local/share/glib-2.0/schemas/"
    elif [ -f ${FSMNT}/usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml ] ; then
      sed -i '' "s/value="\""us"\""/value="\""${KXLAYOUT}"\""/g" ${FSMNT}/usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml
      sed -i '' "s/value="\"""\""/value="\""${KEYVAR}"\""/g" ${FSMNT}/usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml
    fi
  fi

};

localize_key_layout()
{

  KEYLAYOUT="$1"

  # Set the keylayout in rc.conf
  case ${KEYLAYOUT} in
    ca) KEYLAYOUT_CONSOLE="ca-fr.kbd" ;;
    et) KEYLAYOUT_CONSOLE="ee.kbd" ;;
    es) KEYLAYOUT_CONSOLE="es.acc.kbd" ;;
    gb) KEYLAYOUT_CONSOLE="uk.kbd" ;;
     *)  if [ ! -z "${KEYLAYOUT}" ]
         then
           KEYLAYOUT_CONSOLE="${KEYLAYOUT}.kbd"
         fi
        ;;
  esac

  if [ -n "${KEYLAYOUT_CONSOLE}" ]
  then
    echo "keymap=\"${KEYLAYOUT_CONSOLE}\"" >>${FSMNT}/etc/rc.conf
  fi

};

#  Function which prunes other l10n files from the KDE install
localize_prune_langs()
{
  get_value_from_cfg localizeLang
  KEEPLANG="$VAL"
  if [ -z "$KEEPLANG" ] ; then
    KEEPLANG="en"
  fi
  export KEEPLANG

  echo_log "Pruning other l10n files, keeping ${KEEPLANG}"

  # Create the script to do uninstalls
  echo '#!/bin/sh

  for i in `pkg_info -xEI kde-l10n`
  do
    echo "$i" | grep "${KEEPLANG}-kde"
    if [ $? -ne 0 ] ; then
      pkg_delete ${i}
    fi
  done
  ' > ${FSMNT}/.pruneLangs.sh

  chmod 755 ${FSMNT}/.pruneLangs.sh
  chroot ${FSMNT} /.pruneLangs.sh >/dev/null 2>/dev/null
  rm ${FSMNT}/.pruneLangs.sh

};

# Function which sets the timezone on the system
set_timezone()
{
  TZONE="$1"
  cp ${FSMNT}/usr/share/zoneinfo/${TZONE} ${FSMNT}/etc/localtime
};

# Function which enables / disables NTP
set_ntp()
{
  ENABLED="$1"
  if [ "$ENABLED" = "yes" -o "${ENABLED}" = "YES" ]
  then
    if [ "${INSTALLTYPE}" = "FreeBSD" ] ; then
      cat ${FSMNT}/etc/rc.conf 2>/dev/null | grep -q 'ntpd_enable="YES"' 2>/dev/null
      if [ $? -ne 0 ]
      then
        echo 'ntpd_enable="YES"' >> ${FSMNT}/etc/rc.conf
        echo 'ntpd_sync_on_start="YES"' >> ${FSMNT}/etc/rc.conf
      fi
    else
      run_chroot_cmd rc-update add ntpd default
      run_chroot_cmd sysrc -f /etc/rc.conf ntpd_sync_on_start="YES"
    fi
  else
    cat ${FSMNT}/etc/rc.conf 2>/dev/null | grep -q 'ntpd_enable="YES"' 2>/dev/null
    if [ $? -ne 0 ]
    then
      sed -i.bak 's|ntpd_enable="YES"||g' ${FSMNT}/etc/rc.conf
    fi
  fi
};

# Starts checking for localization directives
run_localize()
{
  KEYLAYOUT="NONE"
  KEYMOD="NONE"
  KEYVAR="NONE"

  while read line
  do
    # Check if we need to do any localization
    echo $line | grep -q "^localizeLang=" 2>/dev/null
    if [ $? -eq 0 ]
    then

      # Set our country / lang / locale variables
      get_value_from_string "$line"
      LOCALE=${VAL}
      export LOCALE

      get_value_from_string "$line"
      # If we are doing TrueOS install, localize it as well as FreeBSD base
      if [ "${INSTALLTYPE}" != "FreeBSD" ]
      then
        localize_pcbsd "$VAL"
      fi

      # Localize FreeBSD
      localize_freebsd "$VAL"

      # Localize any X pkgs
      localize_x_desktops "$VAL"
    fi

    # Check if we need to do any keylayouts
    echo $line | grep -q "^localizeKeyLayout=" 2>/dev/null
    if [ $? -eq 0 ] ; then
      get_value_from_string "$line"
      KEYLAYOUT="$VAL"
    fi

    # Check if we need to do any key models
    echo $line | grep -q "^localizeKeyModel=" 2>/dev/null
    if [ $? -eq 0 ] ; then
      get_value_from_string "$line"
      KEYMOD="$VAL"
    fi

    # Check if we need to do any key variant
    echo $line | grep -q "^localizeKeyVariant=" 2>/dev/null
    if [ $? -eq 0 ] ; then
      get_value_from_string "$line"
      KEYVAR="$VAL"
    fi


    # Check if we need to set a timezone
    echo $line | grep -q "^timeZone=" 2>/dev/null
    if [ $? -eq 0 ] ; then
      get_value_from_string "$line"
      set_timezone "$VAL"
    fi

    # Check if we need to set a timezone
    echo $line | grep -q "^enableNTP=" 2>/dev/null
    if [ $? -eq 0 ] ; then
      get_value_from_string "$line"
      set_ntp "$VAL"
    fi
  done <${CFGF}

  if [ "${INSTALLTYPE}" != "FreeBSD" ] ; then
    # Do our X keyboard localization
    localize_x_keyboard "${KEYMOD}" "${KEYLAYOUT}" "${KEYVAR}"
  fi

  # Check if we want to prunt any other KDE lang files to save some disk space
  get_value_from_cfg localizePrune
  if [ "${VAL}" = "yes" -o "${VAL}" = "YES" ] ; then
    localize_prune_langs
  fi

  # Update the login.conf db, even if we didn't localize, its a good idea to make sure its up2date
  run_chroot_cmd "/usr/bin/cap_mkdb /etc/login.conf" >/dev/null 2>/dev/null

};
