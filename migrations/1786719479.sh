echo "Replace the Gemini coding agent with Antigravity"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

agent_file="$HOME/.config/omarchy/defaults/agent"
skills_source="$OMARCHY_PATH/default/agents/skills"

selected_agent=""
if [[ -f $agent_file ]]; then
  read -r selected_agent <"$agent_file" || true
fi

if omarchy-cmd-missing agy &&
  { [[ $selected_agent == "gemini" ]] || [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; }; then
  omarchy-mise-install antigravity-cli agy
fi

if [[ $selected_agent == "gemini" ]]; then
  printf '%s\n' agy >"$agent_file"
fi

if [[ -f $HOME/.local/bin/gemini ]] && grep -Eq '^mise use -g .*"gemini"' "$HOME/.local/bin/gemini"; then
  rm -f "$HOME/.local/bin/gemini"
fi

if [[ -d $skills_source ]]; then
  mkdir -p "$HOME/.gemini/config/skills"
  for skill in "$skills_source"/*/; do
    [[ -d $skill ]] || continue
    name=${skill%/}
    ln -sfn "$name" "$HOME/.gemini/config/skills/${name##*/}"
  done
fi
