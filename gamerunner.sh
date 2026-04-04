#!/usr/bin/env bash

set -e

e="\e[1;31m"
s="\e[1;32m"
n="\e[1;36m"
c="\e[0m"

__error_g()
{
  echo -e "[${e}E$c] Error: $1" >&2
  return 1
}

# mount Squashfs
# $1 - Archive
# $2 - Mountpoint
__mount_squashfs()
{ 
  if [[ ! -d $2 ]]; then
    echo -e "[${n}*$c] Creating mountpoint..." 
    mkdir -p $2
  fi

  if [[ ! -f $1 ]]; then
    __error_g "Archive file does not exist!"
  fi

  echo -ne "[${n}*$c] Mounting Squashfs..."
  if [[ $(findmnt -M $2) ]]; then
      echo -e " already mounted!"
    else
      squashfuse $1 $2
      echo -e " mounted!"
  fi
     
}

# run game
# $1 proton
# $2 proton prefix
# $3 game_exe
__run_game()
{
  proton=$1
  prefix=$2
  gameex=$3
  shift 3
  if [[ ! -f "$proton" ]]; then
    __error_g "Proton executable does not exist!"
  fi

  if [[ ! -d "$prefix" ]]; then
     echo -e "[${n}*$c] Creating Proton prefix..." 
  fi

  if [[ ! -f "$gameex" ]]; then
    __error_g "game executable does not exist!"
  fi

 STEAM_COMPAT_DATA_PATH="$prefix" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$prefix" \
    "$proton" run "$gameex" $@ 
}

# run game in GRE namespace
# $1 - game id
# $2 - proton
# $3 - proton prefix
# $4 - game_exe
__run_game_ns()
{
  gameid="$1"
  proton="$2"
  prefix="$3"
  gameex="$4"
  shift 3
  if [[ ! -f "nsutil.sh" ]]; then
    __error_g "nsutil.sh does not exist!"
  fi
  echo -ne "[${n}*$c] Creating namespace... "
  if [[ -f "/tmp/netns/$gameid.lock" ]]; then
    echo "using the already existing namespace!"
  else
    sudo bash nsutil.sh gresetup up "$gameid" game.cfg
  fi
  echo -e "[${s}D$c] Starting Game..."

  if [[ ! -f "$proton" ]]; then
    __error_g "Proton executable does not exist!"
  fi

  if [[ ! -d "$prefix" ]]; then
     echo -e "[${n}*$c] Creating Proton prefix..." 
  fi

  if [[ ! -f "$gameex" ]]; then
    __error_g "game executable does not exist!"
  fi
  sudo bash nsutil.sh nsproton "$gameid" "$USER" "$proton" "$prefix" "$gameex" $@
}


# -- Main program --

if [[ ! -f "game.cfg" ]]; then
  __error_g "game config does not exist!"
fi

source game.cfg

if [[ $1 == "down" && $USE_NS -eq 1 && $GAMEID != "" ]]; then
  sudo bash nsutil.sh gresetup down $GAMEID game.cfg
  exit 0
fi

if [[ $ARCHIVE != "" && $MOUNTPOINT != "" ]]; then
  __mount_squashfs $ARCHIVE $MOUNTPOINT
fi

if [[ $USE_NS -eq 1 ]]; then
  __run_game_ns $GAMEID "$PROTON_EX" "$PREFIX" "$GAME_EXEC" $GAME_ARGS
else
  __run_game "$PROTON_EX" "$PREFIX" "$GAME_EXEC" $GAME_ARGS
fi

