if grep -qi synaptics "${OMARCHY_SYNAPTIC_INPUT_DEVICES:-/proc/bus/input/devices}" \
   && ! lsmod | grep -q '^psmouse' \
   && modprobe -qn psmouse; then
  modprobe psmouse synaptics_intertouch=1 ||
    echo "Warning: could not enable Synaptics InterTouch on psmouse" >&2
fi
