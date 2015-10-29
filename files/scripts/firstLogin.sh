#!/bin/bash
UTILDIR="/icpc"

# Set the wallpaper to the "template"
xfconf-query -c xfce4-desktop -p /backdrop/screen0 -rR
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s $UTILDIR/wallpaper.png

# Reload the wallpaper(since it may have changed)
if [ -f "$UTILDIR/teamWallpaper.png" ]; then
    xfconf-query -c xfce4-desktop -p /backdrop/screen0 -rR
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s $UTILDIR/teamWallpaper.png
fi

# Reload xfdesktop to get the background image showing
killall xfdesktop
xfdesktop &
sleep 5
killall xfdesktop
