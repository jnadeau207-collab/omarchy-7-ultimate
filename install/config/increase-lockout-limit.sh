sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth
sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth

sed -i '/pam_faillock\.so preauth/d'  /etc/pam.d/sddm-autologin
sed -i '/pam_faillock\.so authsucc/d' /etc/pam.d/sddm-autologin
sed -i '/auth.*pam_permit\.so/a auth        required    pam_faillock.so authsucc' \
           /etc/pam.d/sddm-autologin
