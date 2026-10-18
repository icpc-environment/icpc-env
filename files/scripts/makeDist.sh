#!/bin/bash
# Cleans up temporary files, etc and makes it ready for imaging

UTILDIR="/icpc"

# remove the git repositories
rm -rf /etc/skel/.git
rm -rf /home/icpcadmin/.git

# Cleanup 'imageadmin' things (if it exists)
if id "imageadmin" >/dev/null 2>&1; then
  killall -9 -u imageadmin
  sleep 5
  rm -rf /home/imageadmin
  userdel imageadmin
fi

# Delete proxy settings for apt(if any)
rm -f /etc/apt/apt.conf.d/01proxy

# Kill all the user processes(and wait for them to die)
killall -9 -u contestant
sleep 5

# Reset the team(and any defaults)
$UTILDIR/scripts/deleteUser.sh

# Forget the team, site and printers (the files generated from them go back to
# their defaults, the printers are deleted below)
$UTILDIR/scripts/icpc-config unset team site printers
$UTILDIR/scripts/icpc-apply

# Delete the printers/printer class
for PRINTER in $(lpstat -v | cut -d ' ' -f 3 | tr -d ':')
do
  lpadmin -x $PRINTER
done
lpadmin -x ContestPrinter

# Empty icpc-printer's archive of printed jobs
if [ -d /var/lib/icpc-printer ]; then
  find /var/lib/icpc-printer -mindepth 1 -delete
fi

# Cleanup apt cache/unnecessary package
apt-get autoremove --purge -y
apt-get clean

# Remove 'apt-get update' data
rm -rf /var/lib/apt/lists
mkdir -p /var/lib/apt/lists/partial

# enable the firewall
$UTILDIR/scripts/firewall enable

# Delete /etc/machine-id so the image generates a new one on boot
echo
echo
mount
echo
echo
# sometimes this is a tmpfs, see https://www.freedesktop.org/software/systemd/man/latest/systemd-machine-id-setup.html
umount /etc/machine-id
echo "" > /etc/machine-id

# make sure wireguard config is wiped so it can be generated for each system on boot
systemctl stop wg-setup
wg-quick down contest
rm -f /etc/wireguard/contest.conf /etc/wireguard/contest.fleet
rm -f /etc/icpc/enrollment-token

# icpc-host-identity makes new ones on the next boot, so no two machines share them
rm -f /etc/ssh/ssh_host_* /etc/ssh/sshd_config.d/ssh_host_cert.conf

# Free up space(just to make the image smaller)
dd if=/dev/zero of=/empty bs=1M || true
rm -f /empty
sync
