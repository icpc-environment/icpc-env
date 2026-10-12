#!/bin/bash

# Forget the team, site and printers (the files generated from them go back to
# their defaults, the printers are deleted below)
/icpc/scripts/icpc-config unset team site printers
/icpc/scripts/icpc-apply

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

# clear the user
/icpc/scripts/deleteUser.sh

# make sure the firewall is on
/icpc/scripts/firewall enable

rm -f /icpc/setup-complete
rm -f /icpc/team-reset-complete

# clear self test report
rm -f /icpc/self_test_report
