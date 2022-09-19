#!/bin/bash

# Remove the team wallpaper
rm -f /icpc/teamWallpaper.png

# Delete the printers/printer class
for PRINTER in $(lpstat -v | cut -d ' ' -f 3 | tr -d ':')
do
  lpadmin -x $PRINTER
done
lpadmin -x ContestPrinter

# clear the user
/icpc/scripts/deleteUser.sh

# make sure the firewall is on
ufw --force enable

rm -f /icpc/setup_complete
rm -f /icpc/TEAM*
rm -f /icpc/SITE

# reset squid autologin
echo "# Placeholder" > /etc/squid/autologin.conf
chmod 640 /etc/squid/autologin.conf
chown root:root /etc/squid/autologin.conf

# clear self test report
rm -f /icpc/self_test_report
