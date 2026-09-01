echo "Install the speaker tuning for XPS 2026 14/16"

if omarchy-audio-tuning match >/dev/null 2>&1; then
  omarchy-pkg-add lsp-plugins-lv2
  omarchy-audio-tuning on
fi
