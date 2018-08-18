#!/bin/bash

SSHPORT=2222
SSHKEY="configs/ssh_key"
PIDFILE="tmp/qemu.pid"
ALIVE=0

function usage() {
  echo "Usage: build-final.sh (32|64)"
  echo "Usage: build-final.sh (i386|amd64)"
  echo ""
  echo "32,i386       Build a 32bit contestant image"
  echo "64,amd64      Build a 64bit contestant image"
  exit 1
}

IMGFILE32="output/$(date +%Y-%m-%d)_image-i386.img"
IMGFILE64="output/$(date +%Y-%m-%d)_image-amd64.img"
while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    32|i386)
      IMGFILE=$IMGFILE32
      BASEIMG="base-i386.img"
      ;;
    64|amd64)
      IMGFILE=$IMGFILE64
      BASEIMG="base-amd64.img"
      ;;
    *)
      usage
      ;;
    esac
    shift
done
if [ -z "$IMGFILE" ]; then
  usage
fi

cp output/$BASEIMG $IMGFILE

function runssh() {
  ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null imageadmin@localhost -p$SSHPORT $@ 2>/dev/null
}

function cleanup() {
  if [ $ALIVE -eq 1 ]; then
    echo "Attempting graceful shutdown"
    runssh sudo poweroff
  else
    echo "Forcing shutdown(poweroff)"
    kill $(cat $PIDFILE)
  fi
  rm -f $PIDFILE
}

function waitforssh() {
  # wait for it to boot
  echo -n "Waiting for ssh "
  TIMEOUT=60
  X=0

  while [[ $X -lt $TIMEOUT ]]; do
    let X+=1
    OUT=$(ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null imageadmin@localhost -p$SSHPORT echo "ok" 2>/dev/null)
    if [[ "$OUT" == "ok" ]]; then
      ALIVE=1
      break
    fi
    echo -n "."
    sleep 1
  done
  echo ""

  if [ $ALIVE -eq 0 ]; then
    echo "Timed out waiting for host to respond"
    cleanup
    exit 1
  else
    echo "Host is alive! You can ssh in now"
  fi
}

qemu-system-x86_64 -smp 1 -m 1024 -drive file="$IMGFILE",index=0,media=disk,format=raw -global isa-fdc.driveA= --enable-kvm -net user,hostfwd=tcp::$SSHPORT-:22 -net nic --daemonize --pidfile $PIDFILE -vnc :0 -vga qxl -spice port=5901,disable-ticketing -usbdevice tablet

ALIVE=0
waitforssh

echo "Running ansible"
INVENTORY_FILE=$(mktemp)
echo "vm ansible_port=$SSHPORT ansible_host=127.0.0.1" > $INVENTORY_FILE
ANSIBLE_HOST_KEY_CHECKING=False time ansible-playbook -i $INVENTORY_FILE --diff --become -u imageadmin --private-key $SSHKEY main.yml
rm -f $INVENTORY_FILE

ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null icpcadmin@localhost -p$SSHPORT sudo reboot
# Wait 5 seconds for reboot to happen so we don't ssh back in before it actually reboots
sleep 5
ALIVE=0
waitforssh

echo "Preparing image for distribution"
ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null icpcadmin@localhost -p$SSHPORT sudo /icpc/scripts/makeDist.sh
ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null icpcadmin@localhost -p$SSHPORT sudo poweroff


echo "Image file created: $IMGFILE($(du -h $IMGFILE | cut -f1))"
exit 0
