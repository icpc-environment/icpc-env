#!/bin/bash

# Kill all the user processes(and wait for them to die)
killall -9 -u contestant
sleep 5

DISK=$(blkid -L "ICPC")
if [[ $? == 0 ]]; then
    echo "Wiping FAT32 Partition"
    umount $DISK
    mkfs.vfat $DISK -n ICPC
fi

# find /home/contestant -type d -exec mountpoint {} \;|grep -v not|cut -d" " -f1|tac|xargs umount
umount -f /home/contestant/.vscode/extensions
sleep 1
umount -f /home/contestant/.vscode/extensions-root
sleep 1

rm -rf /home/contestant/.vscode/extensions-work

# Deletes all files owned by the contestant user, then deletes and recreates the account.
echo "Deleting team files"
find / -user contestant -delete

echo "Deleting contestant user"
userdel contestant
rm -rf /home/contestant

echo "Recreating contestant user"
useradd -d /home/contestant -m contestant -s /bin/bash
passwd -d contestant

# touch a file to indicate that the reset is complete (and give us the timestamp if we need it)
echo "Team account reset: $(date -u)" > /icpc/team-reset-complete
