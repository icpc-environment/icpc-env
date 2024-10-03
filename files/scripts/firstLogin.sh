#!/bin/bash
# Close standard output file descriptor
exec 1<&-
# Close standard error file descriptor
exec 2<&-

# Open standard output as $LOG_FILE file for read and write.
exec 1<>/tmp/firstlogin.log
# Redirect standard error to standard output
exec 2>&1


UTILDIR="/icpc"

if [ -f "$UTILDIR/teamWallpaper.png" ]; then
  BACKGROUND="$UTILDIR/teamWallpaper.png"
else
  # Set the wallpaper to the "template"
  BACKGROUND="$UTILDIR/wallpaper.png"
fi

# wait for xfdesktop to be loaded
echo "Waiting for xfdesktop to be running"
while ! pgrep xfdesktop; do
  sleep 1
done

# wait a few moments for things to load initally
sleep 5

echo "Update the desktop background properties"

screens=$(xrandr | jc --xrandr | jq -r '.screens[] | .screen_number' | sort -u)
monitors=$(xrandr | jc --xrandr | jq -r '.screens[] | .devices[] | .device_name' | sort -u)
for s in $screens; do
  for m in $monitors; do
    echo "Setting background for screen$s/monitor$m"
    xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/last-image --create -t string -s $BACKGROUND
    xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/image-path --create -t string -s $BACKGROUND
    xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/image-style --create -t int -s 3
    for ws in 0 1 2 3; do
      xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/workspace$ws/last-image --create -t string -s $BACKGROUND
      xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/workspace$ws/image-style --create -t int -s 3
      xfconf-query -c xfce4-desktop -p /backdrop/screen$s/monitor$m/workspace$ws/image-path --create -t string -s $BACKGROUND
    done
  done
done

xfdesktop --reload
