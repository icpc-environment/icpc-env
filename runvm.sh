#!/bin/bash

# Default group for the VM in ansible. This lets you use group_vars/$VARIANT for site specific configuration
VARIANT=${1:-all}

SSHPORT=2222
SSHKEY="$PWD/configs/imageadmin-ssh_key"
PIDFILE="tmp/qemu.pid"
SNAPSHOT="-snapshot"
ALIVE=0

BASEIMG="base-amd64.img"

trap ctrl_c INT
function ctrl_c() {
  cleanup
  exit 0
}


function runssh() {
  chmod 0400 "$SSHKEY"
  ssh -i "$SSHKEY" -o BatchMode=yes -o ConnectTimeout=1 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null imageadmin@localhost -p$SSHPORT "$@" 2>/dev/null
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
  TIMEOUT=600
  X=0

  while [[ $X -lt $TIMEOUT ]]; do
    let X+=1
    OUT=$(runssh echo "ok" 2>/dev/null)
    if [[ "$OUT" == "ok" ]]; then
      ALIVE=1
      break
    fi
    echo -n "."
    sleep 5
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

function runansible() {
  echo "Running ansible"
  echo "Started at $(date)"
  INVENTORY_FILE=$(mktemp)
  cat <<EOF > $INVENTORY_FILE
vm ansible_port=$SSHPORT ansible_host=127.0.0.1
[$VARIANT]
vm
EOF
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $INVENTORY_FILE --diff --become -u imageadmin --private-key $SSHKEY --ssh-extra-args="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" main.yml
  rm -f $INVENTORY_FILE
  echo "Ansible finished at $(date)"

  echo "Rebooting..."
  runssh sudo reboot
  # Wait 5 seconds for reboot to happen so we don't ssh back in before it actually reboots
  sleep 5
  ALIVE=0
  waitforssh
}
function launchssh() {
  echo "Launching ssh session"
  ssh -i $SSHKEY -o BatchMode=yes -o ConnectTimeout=1 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null imageadmin@localhost -p$SSHPORT
}

function saveuserhome() {
  echo "pulling contestant home directory changes from inside vm"
  pushd home_dirs/contestant
  GIT_SSH_COMMAND="ssh -i $SSHKEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes " git ls-remote --exit-code virtualmachine
  if [[ $? != 0 ]]; then
    git remote add virtualmachine ssh://imageadmin@localhost:$SSHPORT/home/contestant
  fi
  GIT_SSH_COMMAND="ssh -i $SSHKEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes " git fetch virtualmachine

  echo "run: 'cd home_dirs/contestant && git merge virtualmachine/master' to pull these changes in"
  popd
}

function saveadminhome() {
  echo "pulling admin home directory changes from inside vm"
  pushd home_dirs/admin
  GIT_SSH_COMMAND="ssh -i $SSHKEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes " git ls-remote --exit-code virtualmachine
  if [[ $? != 0 ]]; then
    git remote add virtualmachine ssh://imageadmin@localhost:$SSHPORT/home/icpcadmin
  fi
  GIT_SSH_COMMAND="ssh -i $SSHKEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes " git fetch virtualmachine

  echo "run: 'cd home_dirs/contestant && git merge virtualmachine/master' to pull these changes in"
  popd
}

function setresolution() {
  echo "Setting resolution to 1440x900(temporarily)"
  runssh sudo -u contestant env DISPLAY=:0 xrandr --size 1440x900
}

qemu-system-x86_64 -smp 2 -m 4096 -drive file="output/$BASEIMG",index=0,media=disk,format=qcow2 -global isa-fdc.driveA= --enable-kvm -net user,hostfwd=tcp::$SSHPORT-:22 -net nic --daemonize --pidfile $PIDFILE $SNAPSHOT -vnc :0 -vga qxl -spice port=5901,disable-ticketing -usbdevice tablet
ALIVE=0
waitforssh

CMD=1
while [ $CMD != 0 ]; do
  echo "Select an action"
  echo "    1. Launch SSH Session"
  echo "    2. Run ansible"
  echo "    3. Save contestant home directory"
  echo "    4. Save admin home directory"
  echo "    5. Set resolution(1440x900)"
  echo "    0. Halt VM"
  read -p "Action(Default 1): " CMD
  CMD=${CMD:-1}
  case $CMD in
    0) break ;;
    1) launchssh ;;
    2) runansible ;;
    3) saveuserhome ;;
    4) saveadminhome ;;
    5) setresolution ;;
    *) launchssh ;;
  esac
done

echo
echo
read -p "Press enter to halt"

cleanup
exit 0
