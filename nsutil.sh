#!/usr/bin/env bash

set -e

__error()
{
  echo -e "\e[1;31mError\e[0m: $1" >&2
  return 1
}

if [[ $EUID -ne 0 && $1 != "export" ]]; then
  __error "This script must be run as root!"
  exit 1
fi

# Create lockdir
if [ ! -d "/tmp/netns" ]; then
  mkdir /tmp/netns
fi

# -- Generic private FUN --

__create_ns() 
{
  if [ -f "/tmp/netns/$1.lock" ]; then
    __error "Namespace already active! (/tmp/netns/$1.lock: exists)" 
  fi
  ip netns add $1
  touch /tmp/netns/$1.lock
}

__delete_ns() 
{
  if [ ! -f "/tmp/netns/$1.lock" ]; then
    __error "Namespace is not created by this script! (/tmp/netns/$1.lock: No such file or directory)"
  fi
  if [[ -s "/tmp/netns/$1.lock" ]]; then
    while IFS= read -r line; do
      kill $line
    done < "/tmp/netns/$1.lock"
  fi
  ip netns del $1
  rm /tmp/netns/$1.lock
}

# -- stdns::Subcommand FUN --

__stdns_print_usage ()
{
  echo -e "\e[1;36mUsage\e[0m: stdns <up|down> <namespacename> <interface> <ip>"  
  return 1 
}

__stdns_up ()
{
  __create_ns $1 $2
  ip link set $2 netns $1
  ip netns exec $1 ip link set $2 up
  ip netns exec $1 ip addr add $3 dev $2
  ip netns exec $1 ip a
}

__stdns_down () 
{
  ip netns exec $1 ip link set $2 down
  __delete_ns $1
} 

stdns ()
{
  if [ $# -lt 3 ]; then
    __stdns_print_usage
  fi
  case "$1" in
    up)
      echo "Setting up namespace: $2"
      __stdns_up $2 $3 $4
      echo -e " === \e[1;32mDONE\e[0m ==="
      ;;
    down)
      echo "Removing namespace: $2"
      __stdns_down $2 $3
      echo -e " === \e[1;32mDONE\e[0m ==="
      ;;
    *)
      __stdns_print_usage
      ;;
  esac
}

# -- nsrun::Subcommand FUN --

__nsrun_print_usage()
{
  echo -e "\e[1;36mUsage\e[0m: nsrun <namespace> <user> <command> [<args>]"
  return 1
}

nsrun ()
{
  if [ $# -lt 3 ]; then
    __nsrun_print_usage
  fi
  if [ ! -f "/tmp/netns/$1.lock" ]; then
    __error "Namespace is not created by this script! (/tmp/netns/$1.lock: No such file or directory)"
  fi
  ns=$1
  user=$2
  userid=$(id -u $2)
  shift 2
  ip netns exec $ns sudo -u $user \
    PULSE_SERVER=unix:/run/user/$userid \
    XDG_RUNTIME_DIR=/run/user/$userid \
    $@
}

# -- nsproton::Subcommand FUN --

__nsproton_print_usage ()
{
  echo -e "\e[1;36mUsage\e[0m: nsproton <namespace> <user> <proton> <prefix> <program> [<args>]"
  return 1
}

nsproton ()
{
  if [ $# -lt 5 ]; then
    __nsproton_print_usage
  fi
  if ! compgen -G "/tmp/netns/$1.lock" > /dev/null; then
    __error "Namespace is not created by this script! (/tmp/netns/$1.lock: No such file or directory)"
  fi
  ns=$1
  user=$2
  proton=$3
  prefix=$4
  userid=$(id -u $2)
  shift 4
  ip netns exec $ns sudo -u $user \
    PULSE_SERVER=unix:/run/user/$userid/pulse/native \
    XDG_RUNTIME_DIR=/run/user/$userid \
    STEAM_COMPAT_DATA_PATH="$prefix" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$prefix" \
    $proton run $@
}

# -- gresetup::Subcommand FUN --

__gresetup__print_usage()
{
  echo -e "\e[1;36mUsage\e[0m: gresetup <up|down> <namespace> <peerfile>"
  return 1
}

gresetup()
{
  if [ $# -ne 3 ]; then
    __gresetup__print_usage
  fi
  if [ ! -f $3 ]; then
    __error "Failed to open \"$3\": No such file or directory"
  fi
  source $3
  echo "Loaded configuration $3!"
  case "$1" in
    up)
      echo "Creating namespace: $2"
      __create_ns $2
      for interface in "${INTERFACES[@]}"; do
        declare -n if=$interface
        echo "Creating GRE interface: $interface"
        ip link add $interface type ip6gre local ${if[gre_link]} remote ${if[gre_peer]} ttl 64
        ip link set $interface netns $2
        ip netns exec $2 ip addr add ${if[loc_inet]} dev $interface
        ip netns exec $2 ip link set $interface multicast on
        ip netns exec $2 ip link set $interface up
        ip netns exec $2 ip route add default via ${if[rem_inet]} dev $interface metric ${if[def_metr]}
        echo "Adding keepalive ping to ${if[rem_inet]}..."
        ip netns exec $2 nohup ping ${if[rem_inet]} -i 20 > /dev/null &
        echo "$!" >> /tmp/netns/$2.lock
      done
      ip netns exec $2 ip a
      ip netns exec $2 ip route
      echo -e " === \e[1;32mDONE\e[0m ==="
      ;;
    down)
      for interface in "${INTERFACES[@]}"; do
        echo "Removing GRE interface: $interface"
        ip netns exec $2 ip link del $interface
      done
      echo "Removing namespace: $2"
      __delete_ns $2
      echo -e " === \e[1;32mDONE\e[0m ==="
      ;;
    *)
      __gresetup__print_usage

  esac 
}

# -- Subcommand Dispatcher --

__known_subcommands ()
{
  echo -e " === \e[1;36mKnown subcommands:\e[0m ==="
  echo "stdns       - Create/Remove standard namespace containing an already existing network interface"
  echo "nsrun       - Run a native Linux application in the namespace"
  echo "nsproton    - Run a Proton / Windows application in the namespace"
  echo "gresetup    - Create/Remove a namespace containing predefined GRE tunnels (for LAN-Gaming)"
}

case "$1" in
  stdns)      shift; stdns "$@" ;;
  nsrun)      shift; nsrun "$@" ;;
  nsproton)   shift; nsproton "$@" ;;
  gresetup)   shift; gresetup "$@" ;;
  *)          echo "Unknown subcommand: $1" >&2
              __known_subcommands
              ;;
esac
