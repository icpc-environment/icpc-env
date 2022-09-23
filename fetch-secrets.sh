#!/bin/bash
set -euo pipefail
usage() {
  echo "usage: fetch-secrets.sh <contestid>"
  exit 1
}
[ $# -eq 1 ] || usage

mkdir -p files/secrets

# copy jumpy public key
cp secrets/$1/jumpy@icpc.pub files/secrets/
# copy jumpy user private key + ca certificate signature
cp secrets/$1/jumpy@icpc{,-cert.pub} files/secrets/

# copy icpcadmin@contestmanager public key
cp secrets/$1/icpcadmin@contestmanager.pub files/secrets/
# and private key + ca certificate signature
cp secrets/$1/icpcadmin@contestmanager{,-cert.pub} files/secrets/

# copy public+private host key (and ca certificate signature)
cp secrets/$1/contestant.icpcnet.internal_host_ed25519_key{,.pub,-cert.pub} files/secrets/

# copy public ca
cp secrets/$1/server_ca.pub files/secrets/
echo "done!"
