#!/bin/bash
# Create the ssh CA and keys for a contest in secrets/<contest_id>/
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

usage() {
    echo "make-keys.sh <contest_id>"
    exit 1
}

[ $# -ge 1 ] || usage

# A new CA would lock the contest manager out of every image already built for this contest
if [ -f "$SCRIPT_DIR/$1/server_ca" ]; then
    echo "secrets/$1 already has keys, leaving them alone"
    exit 0
fi

mkdir -p "$SCRIPT_DIR/$1"

pushd "$SCRIPT_DIR/$1" >/dev/null

# This is the key for the icpcadmin to connect to any of the contestant machines
ssh-keygen -q -t ed25519 -N "" \
    -C "icpcadmin@contestmanager (For connecting from the contestmanager to the icpc image)" \
    -f "./icpcadmin@contestmanager"

# create a server CA
ssh-keygen -q -t ed25519 -N "" -f ./server_ca

# generate a host certificate for the contest image
ssh-keygen -q -t ed25519 -N "" -f ./contestant.icpcnet.internal_host_ed25519_key

# Sign it. '*' so it's valid for any hostname - OpenSSH rejects host certificates with no principals
ssh-keygen -q -s ./server_ca -h \
    -I "contestant.icpcnet.internal host key" \
    -n '*' \
    ./contestant.icpcnet.internal_host_ed25519_key

# sign the icpcadmin user key (allowing to log into the icpc machine with root, icpcadmin, or contestant)
ssh-keygen -q -s ./server_ca \
    -I "icpcadmin@contestmanager user key" \
    -n "icpcadmin,root,contestant" \
    ./icpcadmin@contestmanager

popd >/dev/null

echo "Created ssh keys for $1 in secrets/$1 - back this directory up, the contest manager needs it to reach the images"
