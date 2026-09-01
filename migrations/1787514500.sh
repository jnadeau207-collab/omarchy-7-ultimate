echo "Align Qt with packaged quickshell 0.3.1 so the shell can load"

if ! command -v nm >/dev/null || [[ ! -e /usr/lib/libQt6Core.so.6 ]]; then
  exit 0
fi

if ! pacman -Q quickshell >/dev/null 2>&1; then
  exit 0
fi

if [[ $(nm -D /usr/lib/libQt6Core.so.6) == *QUntypedPropertyBindingC1EP23QPropertyBindingPrivate@@Qt_6* ]]; then
  exit 0
fi

sudo pacman -S --noconfirm --needed qt6-base qt6-declarative qt6-svg qt6-5compat
