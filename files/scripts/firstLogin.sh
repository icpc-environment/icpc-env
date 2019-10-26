#!/bin/bash
UTILDIR="/icpc"

# Reload the wallpaper(since it may have changed)
if [ -f "$UTILDIR/teamWallpaper.png" ]; then
    xfconf-query -c xfce4-desktop -p /backdrop/screen0 -rR
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s $UTILDIR/teamWallpaper.png
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-style -s 3
else
  # Set the wallpaper to the "template"
  xfconf-query -c xfce4-desktop -p /backdrop/screen0 -rR
  xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s $UTILDIR/wallpaper.png
  xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-style -s 3
fi

# Reload xfdesktop to get the background image showing
sleep 5
timeout 5 xfdesktop --reload
sleep 5
timeout 5 xfdesktop --reload
