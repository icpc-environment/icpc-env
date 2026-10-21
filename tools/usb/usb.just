# Writing images to usb drives, run as `just usb <recipe>` from the repo root.
# Each defaults to the newest image in output/; the scripts need root, so
# these run them with sudo.

set working-directory := '../..'
set positional-arguments

station := 'sudo env "PATH=$PATH" uv run --script tools/usb/station'

[private]
default:
    @just --list usb

# Split an image into the pieces the other recipes write
prepare *args:
    sudo tools/usb/prepare "$@"

# Write one drive, e.g. `just usb write /dev/sdb`
write device *args:
    sudo tools/usb/write-usb --confirm "$@"

# Write every drive plugged into this machine, as they're plugged in
station *args:
    {{station}} "$@"

# Name this machine's usb ports for the station, by plugging a drive into each
learn:
    {{station}} --learn

# Measure a drive's sequential and random read/write speed (overwrites it unless --read-only)
bench device *args:
    sudo tools/usb/bench "$@"
