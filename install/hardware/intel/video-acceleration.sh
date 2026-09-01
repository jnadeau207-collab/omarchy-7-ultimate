
if INTEL_GPU=$(lspci | grep -iE 'vga|3d|display' | grep -i 'intel'); then
  if [[ ${INTEL_GPU,,} =~ (hd\ graphics|uhd\ graphics|xe|iris|arc|panther\ lake) ]]; then
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  elif [[ ${INTEL_GPU,,} =~ "gma" ]]; then
    omarchy-pkg-add libva-intel-driver
  fi
fi
