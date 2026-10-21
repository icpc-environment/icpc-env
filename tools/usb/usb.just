# Writing images to usb drives, run as `just usb <recipe>` from the repo root.
# Each defaults to the newest image in output/; the scripts need root, so
# these run them with sudo.

set working-directory := '../..'
set positional-arguments

[private]
default:
    @just --list usb

# Split an image into the pieces the other recipes write
prepare *args:
    sudo tools/usb/prepare "$@"

# Write one drive, e.g. `just usb write /dev/sdb`
write device *args:
    sudo tools/usb/write-usb --confirm "$@"
