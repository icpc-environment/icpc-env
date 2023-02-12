#!/bin/bash

# Settings
ISO64="ubuntu-22.04.1-live-server-amd64.iso"
OUT64="unattended-${ISO64}"
IMG64="base-amd64.img"

TMPDIR="tmp"
USERDATA="configs/2204_autoinstall.yaml"
METADATA="configs/2204_metadata"

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

  # Extract the efi partition out of the iso
  read -a EFI_PARTITION < <(parted -m $ISO unit b print | awk -F: '$1 == "2" { print $2,$3,$4}' | tr -d 'B')
  dd if=$ISO of=$TMPDIR/efi.img skip=${EFI_PARTITION[0]} bs=1 count=${EFI_PARTITION[2]}
  # # this is basically /usr/lib/grub/i386-pc/boot_hybrid.img from grub-pc-bin package (we just skip the end bits which xorriso will recreate)
  dd if=$ISO of=$TMPDIR/mbr.img bs=1 count=440


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


  mkdir -p "$CONTENTSDIR/autoinst"
  cp "$USERDATA" "$CONTENTSDIR/autoinst/user-data"
  cp "$METADATA" "$CONTENTSDIR/autoinst/meta-data"
  if [[ $USB_PARTITION == 0 ]]; then
    # remove the ICPC partition from the user-data yaml if we aren't going to use it
    sed -i -e "/USB_PARTITION_ENABLED/d" "$CONTENTSDIR/autoinst/user-data"
  fi


  # Configure grub to start the autoinstall after 3 seconds
  cat <<EOF > "$CONTENTSDIR/boot/grub/grub.cfg"
set timeout=3

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Install Ubuntu Server (Unattended)" {
	set gfxpayload=keep
	linux	/casper/vmlinuz  autoinstall ds=nocloud\;seedfrom=/cdrom/autoinst/ net.ifnames=0 ---
	initrd	/casper/initrd
}
EOF
  set -x

  # Finally pack up an ISO the new way
  xorriso -as mkisofs -r \
    -V 'ATTENDLESS_UBUNTU' \
    -o $OUTISO \
    --grub2-mbr $TMPDIR/mbr.img \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b $TMPDIR/efi.img \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    $CONTENTSDIR
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
  --enable-kvm -m 4096 -global isa-fdc.driveA= \
  -drive file="output/$IMG",index=0,media=disk,format=qcow2 \
  -cdrom $OUTISO -boot order=d \
  -net nic -net user,hostfwd=tcp::5222-:22,hostfwd=tcp::5280-:80 \
  -vga qxl -vnc :0 \
  -usbdevice tablet
# -global isa-fdc.driveA= is used to disable floppy drive(gets rid of a warning message)
