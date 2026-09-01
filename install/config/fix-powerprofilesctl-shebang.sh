if [[ -f /usr/bin/powerprofilesctl ]]; then
  sudo sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
fi
