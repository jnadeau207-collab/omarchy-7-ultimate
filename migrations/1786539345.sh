echo "Announce process crashes and offer an AI diagnosis"

skills_source="$OMARCHY_PATH/default/agents/skills"

if [[ -d $skills_source/diagnose-crash ]]; then
  for skills_dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
    mkdir -p "$skills_dir"
    ln -sfn "$skills_source/diagnose-crash" "$skills_dir/diagnose-crash"
  done
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-crash-watch.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-crash-watch.service \
    "$wants_dir/omarchy-crash-watch.service"
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-crash-watch.service >/dev/null 2>&1 || true
fi
