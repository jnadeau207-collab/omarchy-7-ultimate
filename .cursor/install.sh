#!/bin/bash

set -euo pipefail

OMARCHY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  gawk \
  lua5.4 \
  imagemagick \
  python3 \
  python-is-python3 \
  iproute2 \
  qrencode \
  jq \
  ripgrep \
  git \
  curl \
  ca-certificates

if ! command -v magick >/dev/null && command -v convert >/dev/null; then
  printf '#!/bin/bash\nexec /usr/bin/convert "$@"\n' | sudo tee /usr/local/bin/magick >/dev/null
  sudo chmod +x /usr/local/bin/magick
fi

profile_script="/etc/profile.d/omarchy-dev.sh"
sudo tee "$profile_script" >/dev/null <<EOF
# Added by Omarchy Cloud Agent setup (.cursor/install.sh)
export OMARCHY_PATH="$OMARCHY_PATH"
case ":\$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) export PATH="$OMARCHY_PATH/bin:\$PATH" ;;
esac
EOF
sudo chmod +x "$profile_script"

bashrc="$HOME/.bashrc"
marker="# >>> omarchy dev env >>>"
if ! grep -qF "$marker" "$bashrc" 2>/dev/null; then
  {
    printf '\n%s\n' "$marker"
    printf '[ -f %s ] && source %s\n' "$profile_script" "$profile_script"
    printf '# <<< omarchy dev env <<<\n'
  } >>"$bashrc"
fi

echo "Omarchy Cloud Agent environment ready. OMARCHY_PATH=$OMARCHY_PATH"
