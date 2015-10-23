#!/bin/bash
IMGDIR="/icpc"
NAME=$(zenity --entry --title="Setup Team Name" --text="Enter Team Name(e.g. 'team201')")
echo $NAME > $IMGDIR/TEAM
convert $IMGDIR/wallpaper.png -gravity center -pointsize 100 -stroke '#000C' -strokewidth 2 -annotate 0 $NAME -stroke none -fill white -annotate 0 $NAME $IMGDIR/teamWallpaper.png
