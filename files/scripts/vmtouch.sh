#!/bin/bash
# Load some useful things into the kernels cache
VMTOUCH="/usr/bin/vmtouch -ft"

$VMTOUCH /opt/eclipse # 251M
$VMTOUCH /usr/lib/jvm # 312M
$VMTOUCH /usr/include #  33M


# If we have more than 5 Gb of memory, cache some other stuff
phymem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if  [ "$phymem" -gt "5000000" ]; then
    $VMTOUCH /lib         # 229M
    $VMTOUCH /usr/lib     #   2G
    $VMTOUCH /opt/intellij-idea-community # 968M
fi

# Do these last to make sure they end up in memory
$VMTOUCH /icpc     # 250K
$VMTOUCH /bin      # 12M
$VMTOUCH /usr/bin  # 365M
