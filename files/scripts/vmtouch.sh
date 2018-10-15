#!/bin/bash
# Load some useful things into the kernels cache
VMTOUCH="/usr/bin/vmtouch -t"

$VMTOUCH /opt/eclipse # 251M
$VMTOUCH /usr/lib/jvm # 312M
$VMTOUCH /usr/include #  33M


# If we have more than 2 Gb of memory, cache some other stuff
phymem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if  [ "$phymem" -gt "2000000" ]; then
    $VMTOUCH /lib         # 229M
    $VMTOUCH /usr/lib     #   2G
fi

# Do these last to make sure they end up in memory
$VMTOUCH -f /icpc     # 250K
$VMTOUCH -f /bin      # 12M
$VMTOUCH -f /usr/bin  # 365M
