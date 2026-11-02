#!/bin/bash
# Start orca's own user unit, or stop it if it's already running (bound to Alt+Super+S)
if systemctl --user is-active -q orca.service; then
  systemctl --user stop orca.service
else
  systemctl --user start orca.service
fi
# Update the panel indicator now rather than at its next poll
xfce4-panel --plugin-event=genmon-13:refresh:bool:true
