echo "Keep product launchers executable so Superbar and Start pins can run them"

if [[ -d $OMARCHY_PATH/bin ]]; then
  chmod +x "$OMARCHY_PATH/bin"/omarchy-launch-* 2>/dev/null || true
fi
