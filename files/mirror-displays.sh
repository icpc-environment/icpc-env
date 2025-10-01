#!/bin/bash
function usage() {
  echo "mirror-displays WIDTHxHEIGHT"
  echo ""
  echo "Configures all attached monitors at their preferred"
  echo "resolutions, scaling the desktop to WIDTHxHEIGHT"
  echo ""
  echo "Examples:"
  echo "Given 2 displays, one 1920x1080 and a second 1680x1050"
  echo "the command 'mirror-displays 1680x1050' results in the"
  echo "desktop environment being scaled to 1680x1050 and shown"
  echo "on each display. On the 1920x1080 display the desktop"
  echo "will be scaled up to fit the screen, while it will be"
  echo "shown without scaling on the other screen."
  echo ""
  exit 1
}

[ -z "$1" ] && usage
# set all displays to the same resolution
RESOLUTION="$1"
xrandr | awk '/ connected /{ print$1 }' | xargs -n 1 -- bash -xc "xrandr --output \$0 --auto --pos 0x0 --rotate normal --scale-from $RESOLUTION"
