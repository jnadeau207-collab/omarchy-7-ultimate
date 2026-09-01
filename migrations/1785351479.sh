echo "Drop Kvantum now that Qt apps follow the theme through the GTK platform theme"

targets=()
for pkg in kvantum-qt5 kvantum; do
  pacman -Q "$pkg" &>/dev/null && targets+=("$pkg")
done

if ((${#targets[@]})); then
  if pacman -Rs --print "${targets[@]}" >/dev/null 2>&1; then
    sudo pacman -Rns --noconfirm "${targets[@]}" ||
      echo "Could not remove Kvantum; leaving it installed." >&2
  else
    echo "Something still depends on Kvantum; leaving it installed." >&2
  fi
fi
