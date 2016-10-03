#!/bin/sh
# Used to reset the machines between the practice round and actual contest
/icpc/scripts/deleteUser.sh

echo "Done. Rebooting..."
sleep 3
reboot now
