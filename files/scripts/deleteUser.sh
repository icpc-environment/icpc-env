#!/bin/bash
echo "Wiping FAT32 Partition"
DISK=$(blkid -L "ICPC")
umount $DISK
mkfs.vfat $DISK -n ICPC

# Deletes all files owned by the contestant user, then deletes and recreates the account.
echo "Deleting team files"
find / -user contestant -delete

echo "Deleting contestant user"
userdel contestant
rm -rf /home/contestant

echo "Recreating contestant user"
useradd -d /home/contestant -m contestant -G lpadmin -s /bin/bash
passwd -d contestant
