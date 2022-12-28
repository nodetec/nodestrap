#!/bin/bash

# TODO: prompt user top disable wireless interface
# TODO: Klayperson: bro just write the whole script as sudo and put at the top [[ $UID == 0 ]] || sudo "$0"
# TODO: route ssh through tor
# TODO: script must now be run as sudo

system_update() {
  sudo apt update
  sudo apt full-upgrade
  # TODO: Should all packages be installed here or should some be optional and installed in specific functions?
  sudo apt install -y wget curl gpg git openssh-server dphys-swapfile --install-recommends
}

cpu_architecture=

detect_cpu_architecture() {
  cpu_architecture=$(dpkg --print-architecture)
}

# TODO: Check if ssh is already enabled and started by default and that openssh-server should be used
enable_and_start_ssh() {
  systemctl status sshd
  sudo systemctl enable --now sshd
  sudo systemctl start sshd
}

check_usb3_drive_performance() {
  # TODO: Make measuring the speed of external drive optional?
  sudo apt install -y hdparm

  # TODO: Instead of prompting for user input make an informed guess on which drive they're using and ask them for
  # confirmation, if they're using a different drive then allow them to input it?
  # TODO: Check if someone is using an external drive or an internal drive?
  # TODO: Allow someone to use a slow external drive

  name=
  name_confirmation=
  speed_confirmation=

  # TODO: Improve prompts
  # TODO: Something better than using echo for new lines?
  echo
  echo "Measuring the speed of your drive..."

  echo
  echo "If the measured speed is more than 50MB/s, then no further action is needed"

  # TODO: Configure the USB driver to ignore UAS interface
  # TODO: Make this optional?
  echo
  echo "If the measured speed is not ideal, then we can configure the USB driver to ignore the UAS interface if using an external drive"

  echo
  lsblk -pli

  # TODO: Improve example
  echo
  read -p "Enter the name of the partition being used to store the data for the node, for example, /dev/sda: " name

  while true
  do
    # TODO: Standard values for confirmation?
    echo
    read -r -p "Is $name correct? [Y/n] " name_confirmation

    case $name_confirmation in
      [yY][eE][sS]|[yY]|"")
        # TODO: Catch input error to prompt again for a valid name, currently it stops the script
        sudo hdparm -t --direct $name
        echo
        # TODO: If the speed is not ideal, then ask if they want to configure the USB driver to ignore UAS interface
        # Only ask if using an external drive since internal drive should be faster and be handled differently
        read -p "Is measured speed more than 50MB/s? [Y/n] " speed_confirmation
        echo
        break
        ;;
      [nN][oO]|[nN])
        echo
        read -p "Re-enter the name: " name
        ;;
      *)
        # TODO: More descriptive
        # TODO: Allow them to cancel the measurement and continue with script?
        echo
        echo "Invalid input..."
        ;;
    esac
  done
}

create_data_dir() {
  sudo mkdir /data
  sudo chown "$USER":"$USER" /data
}

dynamic_swap() {
  sudo update-rc.d dphys-swapfile enable
  # TODO: Check restricting to config limit value of 2048MB, the config limit can be updated in dphys-swapfile
  sudo sed -i '/CONF_SWAPSIZE/s//#&/' /etc/dphys-swapfile
  sudo dphys-swapfile install
  sudo systemctl restart dphys-swapfile.service
}

enable_firewall() {
	sudo apt install -y ufw
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	sudo ufw allow ssh
	sudo ufw logging off
	sudo ufw enable

	sudo systemctl enable ufw
}

install_fail2ban() {
	sudo apt install -y fail2ban
}

increase_open_files_limit() {
	sudo mkdir -p /etc/security/limits.d
	cat <<EOF | sudo tee /etc/security/limits.d/90-limits.conf
*    soft nofile 128000
*    hard nofile 128000
root soft nofile 128000
root hard nofile 128000
EOF
	# TODO: find out a way to not hardcode the line numbers
	# Hardcoded numbers will cause an issue when rerunning the script
	# Temporary fix: Can comment them out after running the commands or remove these lines from the files after adding them
	sudo sed -i "25i session required	pam_limits.so" /etc/pam.d/common-session
	sudo sed -i "25i session required	pam_limits.so" /etc/pam.d/common-session-noninteractive
}

prepare_nginx_reverse_proxy() {
	sudo apt install -y nginx
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
	sudo apt install -y apt-transport-https
  # TODO: tor may be the only reason why the script needs to be ran with sudo
	cat <<EOF | sudo tee /etc/apt/sources.list.d/tor.list
deb     [arch=$cpu_architecture signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
deb-src [arch=$cpu_architecture signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
EOF

	sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
	sudo apt update
	sudo apt install -y tor deb.torproject.org-keyring
	sudo sed -i '/ControlPort 9051/s/^#//g' /etc/tor/torrc
	sudo sed -i '/CookieAuthentication 1/s/^#//g' /etc/tor/torrc
	# TODO: Find out a way to not hardcode the line number (may work by adding it to the end of the file)
	sudo sed -i "61i CookieAuthFileGroupReadable 1" /etc/tor/torrc

	sudo systemctl reload tor
}

system_update
detect_cpu_architecture
enable_and_start_ssh
check_usb3_drive_performance
create_data_dir
dynamic_swap
enable_firewall
install_fail2ban
increase_open_files_limit
prepare_nginx_reverse_proxy
install_tor
