#!/bin/bash
# xfce4-genmon command: an orca icon in the panel while the screen reader runs, nothing otherwise
if systemctl --user is-active -q orca.service; then
  # SIGUSR1 makes orca open its preferences
  echo "<icon>orca</icon><iconclick>systemctl --user kill -s USR1 --kill-whom=main orca.service</iconclick>"
  echo "<tool>Screen reader on. Click for its settings. Alt+Super+S or Settings &gt; Screen Reader On/Off turns it off</tool>"
else
  # With no output at all genmon shows "XXX"
  echo "<txt></txt>"
fi
