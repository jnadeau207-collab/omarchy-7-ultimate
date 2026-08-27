#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

node "$ROOT/test/shell.d/domain-product-model-test.js"

pass "Files, Software Center, and Compatibility Center models enforce closed read-only state machines"
