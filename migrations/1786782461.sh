echo "Remove the literal \\n[text-bindings] line an earlier migration wrote into foot.ini"

foot_config="$HOME/.config/foot/foot.ini"

if [[ -f $foot_config ]] && grep -qxF '\n[text-bindings]' "$foot_config"; then
  sed -i '/^\\n\[text-bindings\]$/d' "$foot_config"
fi
