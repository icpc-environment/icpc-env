#!/bin/bash

SSHPORT=2222
SSHKEY="configs/ssh_key"
PIDFILE="tmp/qemu.pid"
SNAPSHOT="-snapshot"
ALIVE=0

function usage() {
  echo "Usage: test-final.sh (32|64)"
  echo "Usage: test-final.sh (i386|amd64)"
  echo ""
  echo "32,i386       Test a 32bit contestant image"
  echo "64,amd64      Test a 64bit contestant image"
  exit 1
}

while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    32|i386)
      BASEIMG="*_image-i386.img"
      ;;
    64|amd64)
      BASEIMG="*_image-amd64.img"
      ;;
    *)
      usage
      ;;
    esac
    shift
done
if [ -z "$BASEIMG" ]; then
  usage
fi

function launchssh() {
  echo "Launching ssh session"
  ssh -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null icpcadmin@localhost -p$SSHPORT
}
function cleanup() {
  echo "Forcing shutdown(poweroff)"
  kill $(cat $PIDFILE)
  rm -f $PIDFILE
}

set -x
qemu-system-x86_64 -smp 1 -m 1024 -hda output/$BASEIMG -global isa-fdc.driveA= --enable-kvm -net user,hostfwd=tcp::$SSHPORT-:22 -net nic --daemonize --pidfile $PIDFILE $SNAPSHOT -vnc :0 -vga qxl -spice port=5901,disable-ticketing -usbdevice tablet
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
