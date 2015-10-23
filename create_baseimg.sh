#!/bin/bash

# Settings
ISO64="ubuntu-14.04.3-server-amd64.iso"
ISO32="ubuntu-14.04.3-server-i386.iso"
OUT32="unattended-i386.iso"
OUT64="unattended-amd64.iso"
IMG32="base-i386.img"
IMG64="base-amd64.img"
TMPDIR="tmp"
KICKSTART="configs/1404_ks.cfg"
PRESEED="configs/1404_install.seed"

function usage() {
  echo "Usage: create_baseimage.sh (32|64) [-s size]"
  echo "Usage: create_baseimage.sh (i386|amd64) [-s size]"
  echo ""
  echo "32,i386       Build a 32bit base image"
  echo "64,amd64      Build a 64bit base image"
  echo "-s|--size n   Size of the resulting image(default 7200M)"
  exit 1
}

while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
    32|i386)
      ISO=$ISO32
      OUTISO=$OUT32
      IMG=$IMG32
      ;;
    64|amd64)
      ISO=$ISO64
      OUTISO=$OUT64
      IMG=$IMG64
      ;;
    -s|--size)
      IMGSIZE=$2
      shift
      ;;
    *)
      usage
      ;;
    esac
    shift
done

# Make sure one of the bitness options was set
if [ -z "$ISO" ]; then
  usage
fi

# Default image size 7200M(fits on an 8G flash drive)
IMGSIZE=${IMGSIZE:-7200M}

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

cp "$KICKSTART" "$CONTENTSDIR/ks.cfg"
cp "$PRESEED" "$CONTENTSDIR/ks.preseed"

cat <<EOF > "$CONTENTSDIR/isolinux/txt.cfg"
default install
label install
  menu label ^Install Ubuntu Server (Unattended)
  kernel /install/vmlinuz
  append initrd=/install/initrd.gz ks=cdrom:/ks.cfg preseed/file=/cdrom/ks.preseed --
label memtest
  menu label Test ^memory
  kernel /install/mt86plus
EOF

cat <<EOF > "$CONTENTSDIR/isolinux/isolinux.cfg"
# D-I config version 2.0
include menu.cfg
default vesamenu.c32
prompt 0
# 5 seconds
timeout 50
ui gfxboot bootlogo
EOF

mkisofs -r -V "ATTENDLESS_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -quiet -o $OUTISO $CONTENTSDIR

# cleanup
rm -rf "$CONTENTSDIR"

# Install that base image
rm -f "output/$IMG"
qemu-img create -f raw -o size="$IMGSIZE" "output/$IMG"
qemu-system-x86_64 -m 1024 -hda "output/$IMG" -cdrom $OUTISO -boot order=d --enable-kvm -global isa-fdc.driveA=
# -global isa-fdc.driveA= is used to disable floppy drive
