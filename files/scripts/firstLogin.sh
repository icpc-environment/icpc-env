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
xfconf-query -c xfce4-desktop -p /backdrop/screen0 -rR
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/last-image --create -t string -s $BACKGROUND
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path --create -t string -s $BACKGROUND
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-style --create -t int -s 3

# Reload xfdesktop to get the background image showing (--reload doesn't work, have to --quit first...)
echo "Reload xfdesktop to refresh the background"
sleep 5
xfdesktop --quit
timeout 5 xfdesktop --reload
sleep 5
xfdesktop --quit
timeout 5 xfdesktop --reload

