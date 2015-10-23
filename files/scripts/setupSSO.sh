#!/bin/bash
# Lets the users use SSO autologin
#username=$(zenity --entry --title="DOMjudge Autologin" --text="Enter DOMjudge username:" --entry-text="")
username=$(head -n1 /icpc/TEAM)
password=$(zenity --entry --hide-text --title="DOMjudge Autologin" --text="Enter DOMjudge password:")

# No credentials entered, skip setting this up
if [ -z "$username" ] || [ -z "$password" ]; then
  exit 0
fi

#base64 encode the password to prevent any issues
b64pass=$(echo -n "$password" | openssl base64)

cat > /etc/squid3/autologin.conf <<EOF
request_header_add X-DOMjudge-Autologin true autologin
request_header_add X-DOMjudge-Login "$username" autologin
request_header_add X-DOMjudge-Pass "$b64pass" autologin
EOF

# make sure the contestant user can't read the credentials
chmod 640 /etc/squid3/autologin.conf
chown root:root /etc/squid3/autologin.conf

# restart squid to pick up on the changes(start then stop in case squid isn't running)
service squid3 stop
service squid3 start

exit 0
