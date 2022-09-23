#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


usage() {
    echo "gen-secrets.sh <contestid>"
    exit 1
}

[ $# -ge 1 ] || usage

mkdir -p "$SCRIPT_DIR/$1"

pushd "$SCRIPT_DIR/$1"

# This is the key for contestant to jumpbox (to provision wireguard, run ansible-pull, and set up a reverse ssh tunnel)
ssh-keygen -t ed25519 -N "" \
    -C "jumpy@icpc (For connecting to the contestmanager)" \
    -f "./jumpy@icpc"

# This is the key for the icpcadmin to connect to any of the contestant machines
ssh-keygen -t ed25519 -N "" \
    -C "icpcadmin@contestmanager (For connecting from the contestmanager to the icpc image)" \
    -f "./icpcadmin@contestmanager"

# create a server CA
ssh-keygen -t ed25519 -N "" -f ./server_ca

# generate a host certificate for the contest image
ssh-keygen -t ed25519 -N "" -f ./contestant.icpcnet.internal_host_ed25519_key

# and for the contestmanager machine
ssh-keygen -t ed25519 -N "" -f ./contestmanager.icpcnet.internal_host_ed25519_key

# Sign the host certificates
ssh-keygen -s ./server_ca -h \
    -I "contestant.icpcnet.internal host key" \
    -h ./contestant.icpcnet.internal_host_ed25519_key
    # don't specify a set of principals, so it's valid for any hostname
    # -n "contestant,contestant.icpcnet.internal"

ssh-keygen -s ./server_ca -h \
    -I "contestmanager.icpcnet.internal host key" \
    -n "contestmanager,contestmanager.icpcnet.internal,icpc.cloudcontest.org" \
    ./contestmanager.icpcnet.internal_host_ed25519_key

# sign the icpcadmin user key (allowing to log into the icpc machine with root, icpcadmin, or contestant)
ssh-keygen -s ./server_ca \
    -I "icpcadmin@contestmanager user key" \
    -n "icpcadmin,root,contestant" \
    ./icpcadmin@contestmanager

# sign the jumpy key allowing the icpc machines to connect to the contestmanager machine (as jumpy, wg_client, or git)
ssh-keygen -s ./server_ca \
    -I "jumpy@icpc key" \
    -n "jumpy,wg_client,git" \
    ./jumpy@icpc

popd
