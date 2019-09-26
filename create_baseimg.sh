#!/bin/bash

# Settings
ISO64="ubuntu-18.04.3-server-amd64.iso"
OUT64="unattended-ubuntu-18.04.3-amd64.iso"
IMG64="base-amd64.img"

TMPDIR="tmp"
KICKSTART="configs/1804_ks.cfg"
PRESEED="configs/1804_install.seed"

function usage() {
  echo "Usage: create_baseimage.sh [-s size]"
  echo ""
  echo "-s|--size n   Size of the resulting image(default 14700M)"
  exit 1
}

ISO=$ISO64
OUTISO=$OUT64
IMG=$IMG64

while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
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

# Default image size 14700M(fits on an 16G flash drive)
IMGSIZE=${IMGSIZE:-14700M}

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
path
include menu.cfg
default vesamenu.c32
prompt 0
# 5 seconds
timeout 50
ui gfxboot bootlogo
EOF
echo "en" > "$CONTENTSDIR/isolinux/lang"
set -x
mkisofs -r -V "ATTENDLESS_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -quiet -o $OUTISO $CONTENTSDIR
set +x

# cleanup
rm -rf "$CONTENTSDIR"

# Install that base image
rm -f "output/$IMG"
set -x
qemu-img create -f raw -o size="$IMGSIZE" "output/$IMG"
qemu-system-x86_64 \
  --enable-kvm -m 1024 -global isa-fdc.driveA= \
  -drive file="output/$IMG",index=0,media=disk,format=raw \
  -cdrom $OUTISO -boot order=d \
  -net nic -net user,hostfwd=tcp::5222-:22,hostfwd=tcp::5280-:80 \
  -vga qxl -vnc :0 -spice port=5901,disable-ticketing \
  -usbdevice tablet
# -global isa-fdc.driveA= is used to disable floppy drive(gets rid of a warning message)
