#!/bin/bash

# TODO: Klayperson: bro just write the whole script as sudo and put at the top [[ $UID == 0 ]] || sudo "$0"
# TODO: script must now be run as sudo

# TODO: Login with SSH Keys

# TODO: Should specific versions of packages be installed?
# TODO: Try making while loops into a function

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

disable_wireless_interfaces() {
  echo
  echo "In a security-focused device like a bitcoin node, it's recommended to turn off all radios which includes Bluetooth and WiFi"

  echo
  echo "If you're not using either of them, then both should be disabled"

  disable_bluetooth
  disable_wifi
}

disable_bluetooth() {
  # TODO: Check if this works on RPi
  # TODO: Improve prompts

  disable_bluetooth=

  while true
  do
    echo
    read -r -p "Do you want to disable bluetooth [Y/n] " disable_bluetooth

    # TODO: Standard values for confirmation?
    case $disable_bluetooth in
      [yY][eE][sS]|[yY]|"")
	echo
        sudo systemctl disable bluetooth.service
        break
        ;;
      [nN][oO]|[nN])
        echo
        sudo systemctl enable bluetooth.service
	break
        ;;
      *)
        echo
        echo "Invalid input..."
        ;;
    esac
  done
}

disable_wifi() {
  # TODO: Check if this works on RPi
  # TODO: Improve prompts

  echo
  # TODO: Installing another package to handle disabling WiFi, see if we can do it without this package
  # TODO: Allow user to set a static IP Address, can use nmcli
  sudo apt install -y network-manager

  sudo systemctl start NetworkManager.service
  sudo systemctl enable NetworkManager.service

  disable_wifi=

  while true
  do
    echo
    read -r -p "Do you want to disable WiFi [Y/n] " disable_wifi

    # TODO: Standard values for confirmation?
    case $disable_wifi in
      [yY][eE][sS]|[yY]|"")
	echo
	nmcli radio wifi off
        break
        ;;
      [nN][oO]|[nN])
        echo
	nmcli radio wifi on
	break
        ;;
      *)
        echo
        echo "Invalid input..."
        ;;
    esac
  done
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

ssh_remote_access_through_tor() {
  # TODO: Add the lines to torrc, best way to add them, pattern match?
  # TODO: display onion address, tell them to copy it, store it in a safe location, e.g., in a password manager, and tell them how to use it

  enable_ssh_remote_access_through_tor=
  tor_connection_address_confirmation=

  while true
  do
    echo
    read -r -p "Do you want to enable SSH remote access through Tor? [Y/n] " enable_ssh_remote_access_through_tor

    # TODO: Standard values for confirmation?
    case $enable_ssh_remote_access_through_tor in
      [yY][eE][sS]|[yY]|"")
	sudo sed -i "79i HiddenServiceDir /var/lib/tor/hidden_service_sshd/" /etc/tor/torrc
	sudo sed -i "80i HiddenServiceVersion 3" /etc/tor/torrc
	# TODO: Check this IP Address, should local address be used?
	sudo sed -i "81i HiddenServicePort 22 127.0.0.1:22" /etc/tor/torrc
	# TODO: Add a new line
	# sudo sed -i "82i " /etc/tor/torrc

	# TODO: Test that the reloading produces the onion address
	sudo systemctl reload tor

	echo
	echo "Do not share your Tor connection address with anyone!"
	echo
	echo "Be sure to store your Tor connection address in a secure location, e.g., your password manager"
	echo
	echo "Tor connection address: " $(sudo cat /var/lib/tor/hidden_service_sshd/hostname)
	# TODO: If it isn't and they want it to be securely stored then show them how to securely store it
	echo
        read -p "Is your Tor connection address stored in a secure location? [Y/n] " tor_connection_address_confirmation
        break
        ;;
      [nN][oO]|[nN])
        echo
	echo "SSH remote access through Tor not enabled"
	break
        ;;
      *)
        echo
        echo "Invalid input..."
        ;;
    esac
  done
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
disable_wireless_interfaces
install_tor
ssh_remote_access_through_tor
