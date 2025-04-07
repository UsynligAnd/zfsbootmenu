#!/bin/sh
HOSTNAME=$(hostname)
# Fallback in case the hostname is not set or the command fails
if [ -z "$HOSTNAME" ]; then
  HOSTNAME="zfsbootmenu"
fi

/etc/zfsbootmenu/zbm-builder.sh -O --volume=/tmp:/tmp -O --volume=./:/build -O --hostname="$HOSTNAME"
