#!/bin/bash

sudo /icpc/scripts/firewall status
RET=$?
if [[ $RET == 1 ]];then
    zenity --warning --text="Firewall disabled.  Please remember to re-enable it before the contest"
fi
