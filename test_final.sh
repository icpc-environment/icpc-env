#!/bin/bash

VARIANT=${1:-""}

SSHPORT=2222
SSH_ICPCADMIN_KEY="files/secrets/icpcadmin@contestmanager"
PIDFILE="tmp/qemu.pid"
SNAPSHOT="-snapshot"
ALIVE=0

BASEIMG=$(ls -tr output/$VARIANT*image-amd64.img | tail -n1)
echo "Booting $BASEIMG"

function launchssh() {
  echo "Launching ssh session"
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null icpcadmin@localhost -i $SSH_ICPCADMIN_KEY -p$SSHPORT
}
function cleanup() {
  echo "Forcing shutdown(poweroff)"
  kill "$(cat $PIDFILE)"
  rm -f $PIDFILE
}

set -x
qemu-system-x86_64 -smp 2 -m 4096 -hda $BASEIMG -global isa-fdc.driveA= --enable-kvm -net user,hostfwd=tcp::$SSHPORT-:22 -net nic --daemonize --pidfile $PIDFILE $SNAPSHOT -vnc :0 -vga qxl -spice port=5901,disable-ticketing -usbdevice tablet
set +x

CMD=1
while [ $CMD != 0 ]; do
  echo "Select an action"
  echo "    1. Launch SSH Session"
  echo "    0. Halt VM"
  read -p "Action(Default 1): " CMD
  CMD=${CMD:-1}
  case $CMD in
    0) break ;;
    1) launchssh ;;
    *) launchssh ;;
  esac
done

echo
echo
read -p "Press enter to halt"

cleanup
exit 0
