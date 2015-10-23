#!/bin/bash

sudo ufw status | grep 'Status: active' >/dev/null 2>&1
RET=$?
if [[ $RET == 1 ]];then
    zenity --warning --text="Firewall disabled.  Please remember to re-enable it before the contest"
fi
