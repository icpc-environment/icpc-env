#!/bin/bash
# Sign every file in dev/sample-configs with dev/sample-signing-key, the way
# contestforge signs what it publishes. Rerun after editing a sample.
set -euo pipefail

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KEY="$DIR/sample-signing-key"
SAMPLES="$DIR/sample-configs"

# ssh-keygen refuses a private key other users can read, and git doesn't keep the mode
chmod 0600 "$KEY"

find "$SAMPLES" -name '*.json' -print0 | while IFS= read -r -d '' f; do
  rm -f "$f.sig"
  ssh-keygen -q -Y sign -n contestforge -f "$KEY" "$f"
done

# A good signature by the right key, but over another file
cp "$SAMPLES/generic/sysops/config.json.sig" "$SAMPLES/generic/broken/tampered/config.json.sig"

echo "contestforge $(cut -d' ' -f1,2 "$KEY.pub")" > "$DIR/sample-signers"
