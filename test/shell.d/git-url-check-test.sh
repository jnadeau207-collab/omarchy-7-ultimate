#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

check() {
  "$ROOT/bin/omarchy-git-url-check" "$@" 2>&1
}

for url in "ext::sh -c id" "fd::0,1" "gcrypt::x" "a+b::x" "a.b::x" "a-b::x" "1::x"; do
  output=$(check "$url") &&
    fail "omarchy-git-url-check refuses the transport helper '$url'" "$output"
  grep -qF "names a git option or transport helper" <<<"$output" ||
    fail "omarchy-git-url-check names the helper rejection for '$url'" "$output"
done

pass "a <helper>::<address> URL is refused"

for url in "ext://sh -c id" "fd://17" "gcrypt://example.com/x" "zzz://a" "ZZZ://a" "HTTPS://github.com/a/b"; do
  output=$(check "$url") &&
    fail "omarchy-git-url-check refuses the '$url' transport" "$output"
  grep -qF "which Omarchy does not clone from" <<<"$output" ||
    fail "omarchy-git-url-check names the transport rejection for '$url'" "$output"
done

pass "a <scheme>://<address> URL outside git's own transports is refused"

for url in "-x" "--upload-pack=touch /tmp/pwned" "-oProxyCommand=x"; do
  output=$(check "$url") &&
    fail "omarchy-git-url-check refuses the option '$url'" "$output"
done

pass "a URL shaped like a git option is refused"

output=$(check "") && fail "omarchy-git-url-check refuses an empty URL" "$output"
output=$(check) && fail "omarchy-git-url-check refuses a missing URL" "$output"

pass "an empty URL is refused"

for url in \
  "https://github.com/acme/omarchy-weather.git" \
  "http://example.com/a/b.git" \
  "https://user:token@github.com/acme/repo.git" \
  "ssh://git@github.com/acme/repo.git" \
  "ssh://git@[2001:db8::1]:22/org/repo.git" \
  "git://example.com/repo.git" \
  "git+ssh://git@example.com/acme/repo.git" \
  "ssh+git://git@example.com/acme/repo.git" \
  "ftp://example.com/repo.git" \
  "ftps://example.com/repo.git" \
  "file:///home/me/repo" \
  "git@github.com:acme/repo.git" \
  "git@[2001:db8::1]:org/repo.git" \
  "host:-s/foo.git" \
  "/home/me/repo" \
  "./repo" \
  "../repo" \
  "repo"; do
  output=$(check "$url") ||
    fail "omarchy-git-url-check accepts the legitimate URL '$url'" "$output"
done

pass "the URL forms a user pastes are accepted"
