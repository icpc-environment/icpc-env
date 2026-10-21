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

# clear the user (deleteUser.sh also empties icpc-printer's archive)
/icpc/scripts/deleteUser.sh

# make sure the firewall is on
/icpc/scripts/firewall enable

rm -f /icpc/setup-complete
rm -f /icpc/team-reset-complete

# clear self test report
rm -f /icpc/self_test_report
