# The site served from the icpc-environment r2 bucket at
# https://images.cloudcontest.org, run as `just website <recipe>`.

set working-directory := '..'
set positional-arguments

bucket := 's3://icpc-environment'

[private]
default:
    @just --list website

# Serve the site at http://localhost:8000 to preview changes
serve port='8000':
    python3 -m http.server -d website "$1"

# Upload changed files to the bucket, e.g. `just website publish --dryrun`
publish *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source .env-r2
    aws s3 sync website/ {{bucket}}/ \
        --exclude website.just --exclude 'images/*' \
        --cache-control 'public, max-age=300' "$@"
