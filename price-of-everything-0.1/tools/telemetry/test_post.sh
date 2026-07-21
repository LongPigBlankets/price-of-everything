#!/usr/bin/env bash
# PoC test: POST the sample envelope to the deployed Apps Script endpoint.
# Usage: ./test_post.sh "https://script.google.com/macros/s/XXXX/exec"
# Expected output: ok   (-L follows Apps Script's 302 redirect to the response body)
set -euo pipefail
URL="${1:?usage: test_post.sh <web-app /exec URL>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
curl -sS -L -X POST -H "Content-Type: application/json" \
     --data-binary @"$DIR/sample_envelope.json" "$URL"
echo
