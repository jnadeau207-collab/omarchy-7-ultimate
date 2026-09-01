echo "Gate sudo and polkit fingerprint auth behind the lid state (password when the lid is shut)"

gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"

for pam in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
  if [[ -f $pam ]] &&
    grep -q 'pam_fprintd\.so' "$pam" &&
    ! grep -q 'omarchy-hw-laptop-closed' "$pam"; then
    sudo sed -i "/pam_fprintd\.so/i $gate" "$pam"
  fi
done
