#!/bin/bash

# Settings
ISO64="ubuntu-20.04.5-live-server-amd64.iso"
OUT64="unattended-${ISO64}"
IMG64="base-amd64.img"

TMPDIR="tmp"
USERDATA="configs/2004_autoinstall.yaml"
METADATA="configs/2004_metadata"

function usage() {
  echo "Usage: create_baseimage.sh [-s size]"
  echo ""
  echo "-s|--size n   Size of the resulting image(default 14700M)"
  echo "--no-usb      Don't create a fat32 partition for easy usb mounting"
  exit 1
}

ISO=$ISO64
OUTISO=$OUT64
IMG=$IMG64
USB_PARTITION=1

while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    -s|--size)
      IMGSIZE=$2
      shift
      ;;
    --no-usb)
      USB_PARTITION=0
      ;;
    *)
      usage
      ;;
    esac
    shift
done

# Default image size 14700M(fits on an 16G flash drive)
# IMGSIZE=${IMGSIZE:-14700M}
# Default image size 28500M(fits on an 32G flash drive)
IMGSIZE=${IMGSIZE:-28500M}


function create_unattended_iso() {
  CONTENTSDIR="$TMPDIR/contents"
  rm -rf "$CONTENTSDIR"
  mkdir -p "$CONTENTSDIR"


  #Use bsdtar if possible to extract(no root required)
  if hash bsdtar 2>/dev/null; then
    bsdtar xfp $ISO -C $CONTENTSDIR
    chmod -R u+w "$CONTENTSDIR"
  else
    # mount the iso, then copy the contents
    LOOPDIR="$TMPDIR/iso"
    mkdir -p "$LOOPDIR"
    sudo mount -o loop "$ISO" "$LOOPDIR"
    cp -rT "$LOOPDIR" "$CONTENTSDIR"
    sudo umount "$LOOPDIR"
  fi


  # Skip language selection menu
  chmod u+w $CONTENTSDIR/isolinux
  echo "en" > "$CONTENTSDIR/isolinux/lang"

  mkdir -p "$CONTENTSDIR/autoinst"
  cp "$USERDATA" "$CONTENTSDIR/autoinst/user-data"
  cp "$METADATA" "$CONTENTSDIR/autoinst/meta-data"
  if [[ $USB_PARTITION == 0 ]]; then
    # remove the ICPC partition from the user-data yaml if we aren't going to use it
    sed -ie "/partition-icpc/d" "$CONTENTSDIR/autoinst/user-data"
  fi

  cat <<EOF > "$CONTENTSDIR/isolinux/txt.cfg"
default install
label install
  menu label ^Install Ubuntu Server (Unattended)
  kernel /casper/vmlinuz
  append initrd=/casper/initrd autoinstall ds=nocloud-net;seedfrom=/cdrom/autoinst/ net.ifnames=0 --
label memtest
  menu label Test ^memory
  kernel /install/mt86plus
EOF

  cat <<EOF > "$CONTENTSDIR/isolinux/isolinux.cfg"
# D-I config version 2.0
path
include menu.cfg
default vesamenu.c32
prompt 0
# 2.5 seconds
timeout 25
ui gfxboot bootlogo
EOF
  echo "en" > "$CONTENTSDIR/isolinux/lang"
  set -x
  mkisofs -r -V "ATTENDLESS_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -quiet -o $OUTISO $CONTENTSDIR
  set +x

  # cleanup
  rm -rf "$CONTENTSDIR"
}

create_unattended_iso

# Install that base image
rm -f "output/$IMG"
set -x
qemu-img create -f qcow2 -o size="$IMGSIZE" "output/$IMG"
qemu-system-x86_64 \
  --enable-kvm -m 1024 -global isa-fdc.driveA= \
  -drive file="output/$IMG",index=0,media=disk,format=qcow2 \
  -cdrom $OUTISO -boot order=d \
  -net nic -net user,hostfwd=tcp::5222-:22,hostfwd=tcp::5280-:80 \
  -vga qxl -vnc :0 \
  -usbdevice tablet
# -global isa-fdc.driveA= is used to disable floppy drive(gets rid of a warning message)
