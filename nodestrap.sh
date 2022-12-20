#!/bin/bash

# TODO: increase swap maybe
# TODO: promt user to select drive to check drive performance
# TODO: setup ssh
# TODO: prompt user top disable wireless interface
# TODO: Klayperson: bro just write the whole script as sudo and put at the top [[ $UID == 0 ]] || sudo "$0"
# TODO: route ssh through tor

system_update() {
	sudo apt update
	sudo apt full-upgrade
	sudo apt install wget curl gpg git --install-recommends
}

create_data_dir() {
	sudo mkdir /data
	sudo chown "$USER":"$USER" /data
}

enable_firewall() {
	sudo apt install ufw
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	sudo ufw allow ssh
	sudo ufw logging off
	sudo ufw enable

	sudo systemctl enable ufw
}

install_fail2ban() {
	sudo apt install fail2ban
}

increase_open_files_limit() {
	sudo mkdir -p /etc/security/limits.d
	cat <<EOF | sudo tee /etc/security/limits.d/90-limits.conf
*    soft nofile 128000
*    hard nofile 128000
root soft nofile 128000
root hard nofile 128000
EOF

	sudo rm -rf /etc/pam.d/common-session
	cat <<EOF | sudo tee /etc/pam.d/common-session
#
# /etc/pam.d/common-session - session-related modules common to all services
#
# This file is included from other service-specific PAM config files,
# and should contain a list of modules that define tasks to be performed
# at the start and end of interactive sessions.
#
# As of pam 1.0.1-6, this file is managed by pam-auth-update by default.
# To take advantage of this, it is recommended that you configure any
# local modules either before or after the default block, and use
# pam-auth-update to manage selection of other modules.  See
# pam-auth-update(8) for details.

# here are the per-package modules (the "Primary" block)
session [default=1] pam_permit.so
# here's the fallback if no module succeeds
session requisite pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
session required pam_permit.so
# and here are more per-package modules (the "Additional" block)
session required pam_unix.so
session optional pam_systemd.so
session optional pam_chksshpwd.so
session required pam_limits.so

# end of pam-auth-update config
EOF

	sudo rm -rf /etc/pam.d/common-session-noninteractive
	cat <<EOF | sudo tee /etc/pam.d/common-session-noninteractive
#
# /etc/pam.d/common-session-noninteractive - session-related modules
# common to all non-interactive services
#
# This file is included from other service-specific PAM config files,
# and should contain a list of modules that define tasks to be performed
# at the start and end of all non-interactive sessions.
#
# As of pam 1.0.1-6, this file is managed by pam-auth-update by default.
# To take advantage of this, it is recommended that you configure any
# local modules either before or after the default block, and use
# pam-auth-update to manage selection of other modules.  See
# pam-auth-update(8) for details.

# here are the per-package modules (the "Primary" block)
session	[default=1]			pam_permit.so
# here's the fallback if no module succeeds
session	requisite			pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
session	required			pam_permit.so
# and here are more per-package modules (the "Additional" block)
session	required	pam_unix.so 
session required  pam_limits.so
# end of pam-auth-update config# end of pam-auth-update config
EOF

}

prepare_nginx_reverse_proxy() {
	sudo apt install nginx
	sudo openssl req -x509 -nodes -newkey rsa:4096 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/CN=localhost" -days 3650
	sudo mkdir /etc/nginx/streams-enabled
	sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
	cat <<EOF | sudo tee /etc/nginx/nginx.conf
user www-data;
worker_processes 1;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
  worker_connections 768;
}

stream {
  ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
  ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
  ssl_session_cache shared:SSL:1m;
  ssl_session_timeout 4h;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;

  include /etc/nginx/streams-enabled/*.conf;

}
EOF

}

install_tor() {
	sudo apt install apt-transport-https
	# TODO: derive architecture from system
	# Klayperson: for architecture just `lscpu | awk '$1 == "Architecture:" { print $2 }'`
	cat <<EOF | sudo tee /etc/apt/sources.list.d/tor.list
deb     [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
deb-src [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
EOF

	sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
	sudo apt update
	sudo apt install tor deb.torproject.org-keyring
	sudo sed -i '/ControlPort 9051/s/^#//g' /etc/tor/torrc
	sudo sed -i '/CookieAuthentication 1/s/^#//g' /etc/tor/torrc
	echo "CookieAuthFileGroupReadable 1" | sudo tee -a /etc/tor/torrc
	sudo systemctl reload tor
}
