echo "Regenerate mise wrappers that still print mise's own output to stdout"

stale_template() {
  local form=$1 package=$2 bin=$3

  case $form in
  cooldown-export)
    printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  bail-on-failure)
    printf '#!/bin/bash\nmise use -g "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  mise-exec)
    printf '#!/bin/bash\nmise use -g "%s"\nexec mise exec "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  bare-exec)
    printf '#!/bin/bash\nmise use -g "%s"\nexec "%s" "$@"' "$package" "$bin" ;;
  esac
}

bin_dir="$HOME/.local/bin"

[[ -d $bin_dir ]] || exit 0

for wrapper in "$bin_dir"/*; do
  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || continue

  (($(stat -c%s "$wrapper") <= 1024)) || continue

  contents=$(<"$wrapper")

  package=$(sed -n 's/^mise use -g "\(.*\)"\( || exit 1\)*$/\1/p' <<<"$contents")
  bin=$(sed -n \
    -e 's/^exec mise x ".*" -- "\(.*\)" "\$@"$/\1/p' \
    -e 's/^exec mise exec ".*" -- "\(.*\)" "\$@"$/\1/p' \
    -e 's/^exec "\(.*\)" "\$@"$/\1/p' <<<"$contents")

  [[ -n $package && -n $bin ]] || continue

  stale=0
  for form in cooldown-export bail-on-failure mise-exec bare-exec; do
    if [[ $contents == "$(stale_template "$form" "$package" "$bin")" ]]; then
      stale=1
      break
    fi
  done

  ((stale)) || continue

  omarchy-mise-install "$package" "${wrapper##*/}" "$bin"
done
