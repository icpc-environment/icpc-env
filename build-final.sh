#!/bin/bash
set -xeuo pipefail

# Default group for the VM in ansible. This lets you use group_vars/$VARIANT for site specific configuration
VARIANT=${1:-generic}

SSHPORT=2222
SSH_BUILD_KEY="configs/imageadmin-ssh_key"
PIDFILE="tmp/qemu.pid"
ALIVE=0

IMGFILE="output/$(date +%Y-%m-%d)_image-amd64.img"
if [[ $VARIANT != 'all' ]]; then
  IMGFILE="output/$VARIANT-$(date +%Y-%m-%d)_image-amd64.img"
fi

BASEIMG="${BASEIMG:-base-amd64.img}"

# Copy to a raw disk image
qemu-img convert -O raw output/$BASEIMG $IMGFILE

function runssh() {
  ssh -i $SSH_BUILD_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  imageadmin@localhost -p$SSHPORT $@ 2>/dev/null
}

function cleanup() {
  if [ $ALIVE -eq 1 ]; then
    echo "Attempting graceful shutdown"
    runssh sudo poweroff
  else
    echo "Forcing shutdown(poweroff)"
    kill "$(cat $PIDFILE)"
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
    set +e
    OUT=$(ssh -i $SSH_BUILD_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  imageadmin@localhost -p$SSHPORT echo "ok" 2>/dev/null)
    set -e
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

# Cloud builders often have no /dev/kvm, where --enable-kvm is fatal rather than slow
if [ -r /dev/kvm ]; then
  KVMARGS="--enable-kvm"
else
  echo "No /dev/kvm - falling back to emulation, this will be slow"
  KVMARGS=""
fi

qemu-system-x86_64 -smp 2 -m 4096 -drive file="$IMGFILE",index=0,media=disk,format=raw $KVMARGS -net user,hostfwd=tcp::$SSHPORT-:22 -net nic --daemonize --pidfile $PIDFILE -vnc :0 -device VGA,edid=on,xres=1440,yres=900 -usbdevice tablet

ALIVE=0
waitforssh

echo "Running ansible"
INVENTORY_FILE=$(mktemp)
cat <<EOF > $INVENTORY_FILE
vm ansible_port=$SSHPORT ansible_host=127.0.0.1
[$VARIANT]
vm
EOF

ANSIBLE_HOST_KEY_CHECKING=False .venv/bin/ansible-playbook -i $INVENTORY_FILE  --ssh-extra-args="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --diff --become -u imageadmin --private-key $SSH_BUILD_KEY main.yml
rm -f $INVENTORY_FILE

SSH_ICPCADMIN_KEY=$(secrets/admin-key.sh "$VARIANT")

ssh -i $SSH_ICPCADMIN_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  icpcadmin@localhost -p$SSHPORT sudo reboot
# Wait 5 seconds for reboot to happen so we don't ssh back in before it actually reboots
sleep 5
ALIVE=0
waitforssh

# Run the self test and pull the package/module inventory off the image before
# makeDist.sh strips it down, so builds can be diffed against each other.
ssh -i $SSH_ICPCADMIN_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  icpcadmin@localhost -p$SSHPORT sudo bash -c "/icpc/scripts/self_test"
scp -i $SSH_ICPCADMIN_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -P $SSHPORT icpcadmin@localhost:/icpc/filesystem.manifest.amd64.txt output/
scp -i $SSH_ICPCADMIN_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -P $SSHPORT icpcadmin@localhost:/icpc/pypy3.modules.txt output/

echo "Preparing image for distribution"
set -x
ssh -i $SSH_ICPCADMIN_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  icpcadmin@localhost -p$SSHPORT sudo bash -c "/icpc/scripts/makeDist.sh"
ssh -i $SSH_ICPCADMIN_KEY -o BatchMode=yes -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes  icpcadmin@localhost -p$SSHPORT sudo shutdown --poweroff --no-wall +1

# Wait for qemu to exit, see https://unix.stackexchange.com/a/427133
tail --pid=$(cat $PIDFILE) -f /dev/null

# Dig holes in the file to make it sparse (i.e. smaller!)
fallocate -d $IMGFILE
echo "Image file created: $IMGFILE($(du -h $IMGFILE | cut -f1))"

# Opt-in, since it changes what the downstream tooling has to consume.
# pigz rather than gzip so this uses every core: http://zlib.net/pigz/
if [ "${COMPRESS:-0}" != "0" ]; then
  pigz -9 "$IMGFILE"
  echo "Compressed to $IMGFILE.gz($(du -h "$IMGFILE.gz" | cut -f1))"
fi

# Move off our ssd to slow/bulk storage
# mv $IMGFILE output/

exit 0
