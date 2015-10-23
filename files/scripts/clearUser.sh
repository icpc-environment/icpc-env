#!/bin/sh
# Used to reset the machines between the practice round and actual contest

# Delete and recreate user
/icpc/scripts/deleteUser.sh

# Remove firstlogin(To prevent setting up printers/team name), and then reboot to log back in as the team
rm /home/contestant/.firstLogin

echo "Done. Rebooting..."
sleep 3
reboot now
