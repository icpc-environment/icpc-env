#!/bin/bash
# Cleans up temporary files, etc and makes it ready for imaging

UTILDIR="/icpc"

# remove the git repositories
rm -rf /etc/skel/.git
rm -rf /home/icpcadmin/.git

# Cleanup 'imageadmin' things
rm -rf /home/imageadmin
userdel imageadmin

# remove vmtouch git repo
rm -rf /tmp/vmtouch

# Remove scala deb
rm -rf /tmp/scala.deb

# Delete proxy settings for apt(if any)
rm -f /etc/apt/apt.conf.d/01proxy

# Kill all the user processes(and wait for them to die)
killall -9 -u contestant
sleep 5

# Reset the team(and any defaults)
$UTILDIR/scripts/deleteUser.sh

# reset the TEAM and SITE
echo "" > $UTILDIR/TEAM
echo "fit" > $UTILDIR/SITE

# Remove the team wallpaper
rm -f $UTILDIR/teamWallpaper.png

# Delete the printers/printer class
for PRINTER in $(lpstat -v | cut -d ' ' -f 3 | tr -d ':')
do
  lpadmin -x $PRINTER
done
lpadmin -x ContestPrinter

# Remove all but the current kernel(and old kernel headers)
apt-get autoremove --purge linux-image-generic linux-generic
dpkg --list | grep 'linux-image' | awk '{ print $2 }' | sort -V | sed -n '/'"$(uname -r | sed "s/\([0-9.-]*\)-\([^0-9]\+\)/\1/")"'/q;p' | xargs sudo apt-get -y purge
dpkg --list | grep 'linux-headers' | awk '{ print $2 }' | sort -V | sed -n '/'"$(uname -r | sed "s/\([0-9.-]*\)-\([^0-9]\+\)/\1/")"'/q;p' | xargs sudo apt-get -y purge

# Cleanup apt cache/unnecessary package
apt-get autoremove --purge -y
apt-get clean

# Remove 'apt-get update' data
rm -rf /var/lib/apt/lists
mkdir -p /var/lib/apt/lists/partial

# enable the firewall
ufw --force enable
