#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command node

whatsapp_slim_id=$(node - <<'JS' "$ROOT/default/chromium/extensions/whatsapp-slim/manifest.json"
const crypto = require('crypto')
const fs = require('fs')

const manifest = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const hash = crypto.createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest()
const alphabet = 'abcdefghijklmnop'
let id = ''

for (const byte of hash.subarray(0, 16)) {
  id += alphabet[byte >> 4]
  id += alphabet[byte & 0x0f]
}

process.stdout.write(id)
JS
)

[[ $whatsapp_slim_id == "amhpgjbcfakkmkeojmoaoiochhifohdi" ]] ||
  fail "whatsapp-slim extension manifest has the stable id" "$whatsapp_slim_id"
pass "whatsapp-slim extension manifest has the stable id"
