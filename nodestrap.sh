#!/bin/bash

# TODO: Login with SSH Keys

# TODO: Should specific versions of packages be installed?
# TODO: Try making while loops into a function
# TODO: Try making if statements into a function
# TODO: How to route all network traffic over tor?

# TODO: Exit script if anything other than the correct password is entered after three attempts for any of the commands

set_up_sudo_session() {
  printf "sudo permissions needed to set up bitcoin node\n"
  sudo -v
}

system_update() {
  sudo apt update
  sudo apt full-upgrade
  sudo apt install -y wget curl gpg git --install-recommends
}

cpu_architecture=

detect_cpu_architecture() {
  cpu_architecture=$(dpkg --print-architecture)
}

# TODO: Check if ssh is already enabled and started by default, apt should already check if a package is installed, if it is will it update it
# when installing again?
enable_and_start_ssh() {
  sudo apt install -y openssh-server
  systemctl status sshd
  sudo systemctl enable --now sshd
}

check_usb3_drive_performance() {
  # TODO: Make measuring the speed of drive optional?
  sudo apt install -y hdparm

  # TODO: Instead of prompting for user input make an informed guess on which drive they're using and ask them for
  # confirmation, if they're using a different drive then allow them to input it?
  # TODO: Check if someone is using an external drive or an internal drive?
  # TODO: Allow someone to use a slow external drive

  name=
  name_confirmation=
  speed_confirmation=

  # TODO: Improve prompts
  printf "\nMeasuring the speed of your drive... \n\n"

  printf "If the measured speed is more than 50MB/s, then no further action is needed \n\n"

  # TODO: Configure the USB driver to ignore UAS interface
  # TODO: Make this optional?
  printf "If the measured speed is not ideal, then we can configure the USB driver to ignore the UAS interface if using an external drive\n\n"

  lsblk -pli

  # TODO: Improve example
  printf "\n"
  read -p "Enter the name of the partition being used to store the data for the node, for example, /dev/sda: " name

  while true
  do
    # TODO: For confirmations could make the user re-enter what they already inputted
    printf "\n"
    read -r -p "Is $name correct? [Y/n] " name_confirmation

    case $name_confirmation in
      [yY][eE][sS]|[yY]|"")
        # TODO: Catch input error to prompt again for a valid name, currently it stops the script i think?
        sudo hdparm -t --direct $name
        printf "\n"
        # TODO: If the speed is not ideal, then ask if they want to configure the USB driver to ignore UAS interface
        # Only ask if using an external drive since internal drive should be faster and be handled differently
	# TODO: Could get the speed value from the command and evaluate it ourselves
        read -p "Is measured speed more than 50MB/s? [Y/n] " speed_confirmation
        printf "\n"
        break
        ;;
      [nN][oO]|[nN])
        printf "\n"
        read -p "Re-enter the name: " name
        ;;
      *)
        # TODO: More descriptive
        # TODO: Allow them to cancel the measurement and continue with script?
        printf "\nInvalid input...\n"
        ;;
    esac
  done
}

create_data_dir() {
  sudo mkdir /data
  sudo chown "$USER":"$USER" /data
}

dynamic_swap() {
  sudo apt install -y dphys-swapfile
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

  # TODO: Use \t instead of spaces, i.e., session required\tpam_limits.so
  # instead of session required        pam_limits.so
  # TODO: Want to be able to detect the pattern session optional\tpam_systemd.so for common-session
  if ! grep -Fxq "session required	pam_limits.so" /etc/pam.d/common-session
  then
    sudo sed -i '/pam_systemd.so/a session required\tpam_limits.so' /etc/pam.d/common-session
  else
    printf "\n/etc/pam.d/common-session already updated...\n"
  fi

  # TODO: Want to be able to detect the pattern session required\tpam_unix.so for common-session-noninteractive
  if ! grep -Fxq "session required	pam_limits.so" /etc/pam.d/common-session-noninteractive
  then
    sudo sed -i '/pam_unix.so/a session required\tpam_limits.so' /etc/pam.d/common-session-noninteractive
  else
    printf "\n/etc/pam.d/common-session-noninteractive already updated...\n\n"
  fi
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
  printf "\nIn a security-focused device like a bitcoin node, it's recommended to turn off all radios which includes Bluetooth and WiFi\n\n"

  printf "If you're not using either of them, then both should be disabled\n"

  disable_bluetooth
  disable_wifi
}

disable_bluetooth() {
  # TODO: Check if this works on RPi
  # TODO: Improve prompts

  disable_bluetooth=

  while true
  do
    printf "\n"
    read -r -p "Do you want to disable bluetooth [Y/n] " disable_bluetooth

    case $disable_bluetooth in
      [yY][eE][sS]|[yY]|"")
	printf "\n"
        sudo systemctl disable bluetooth.service
        break
        ;;
      [nN][oO]|[nN])
        printf "\n"
        sudo systemctl enable bluetooth.service
	break
        ;;
      *)
        printf "\nInvalid input...\n"
        ;;
    esac
  done
}

disable_wifi() {
  # TODO: Check if this works on RPi
  # TODO: Improve prompts

  printf "\n"
  # TODO: Installing another package to handle disabling WiFi, see if we can do it without this package
  # TODO: Allow user to set a static IP Address, can use nmcli
  sudo apt install -y network-manager

  sudo systemctl start NetworkManager.service
  sudo systemctl enable NetworkManager.service

  disable_wifi=

  while true
  do
    printf "\n"
    read -r -p "Do you want to disable WiFi [Y/n] " disable_wifi

    case $disable_wifi in
      [yY][eE][sS]|[yY]|"")
	printf "\n"
	nmcli radio wifi off
        break
        ;;
      [nN][oO]|[nN])
        printf "\n"
	nmcli radio wifi on
	break
        ;;
      *)
        printf "\nInvalid input...\n"
        ;;
    esac
  done
}

install_tor() {
  sudo apt install -y apt-transport-https
  cat <<EOF | sudo tee /etc/apt/sources.list.d/tor.list
deb 	[arch=$cpu_architecture signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
deb-src [arch=$cpu_architecture signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bullseye main
EOF

  # TODO: Check if the script hangs here, i.e., at the wget and why?
  sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
  sudo apt update
  sudo apt install -y tor deb.torproject.org-keyring
  sudo sed -i '/ControlPort 9051/s/^#//g' /etc/tor/torrc
  sudo sed -i '/CookieAuthentication 1/s/^#//g' /etc/tor/torrc

  if ! grep -Fxq "CookieAuthFileGroupReadable 1" /etc/tor/torrc
  then
    sudo sed -i '/CookieAuthentication 1/a CookieAuthFileGroupReadable 1' /etc/tor/torrc
  else
    printf "\n/etc/tor/torrc already updated...\n"
  fi

  sudo systemctl reload tor
}

ssh_remote_access_through_tor() {
  # TODO: display onion address, tell them to copy it, store it in a safe location, e.g., in a password manager, and tell them how to use it

  enable_ssh_remote_access_through_tor=
  tor_connection_address_confirmation=

  # TODO: If already added to the file don't display the connection
  # address, ask them if they want to display the connection address, if
  # yes display the connection address and ask them if they stored it in
  # a secure location,
  # make a separate function for displaying the connection address if
  # already added to the file
  while true
  do
    printf "\n"
    read -r -p "Do you want to enable SSH remote access through Tor? [Y/n] " enable_ssh_remote_access_through_tor

    case $enable_ssh_remote_access_through_tor in
      [yY][eE][sS]|[yY]|"")

	if ! grep -Fxq "HiddenServiceDir /var/lib/tor/hidden_service_sshd/" /etc/tor/torrc
	then
	  sudo sed -i '/HiddenServicePort 22 127.0.0.1:22/a \\nHiddenServiceDir /var/lib/tor/hidden_service_sshd/' /etc/tor/torrc
	  sudo sed -i '/HiddenServiceDir \/var\/lib\/tor\/hidden_service_sshd\//a HiddenServiceVersion 3' /etc/tor/torrc
	  # TODO: Check this IP Address, should local address be used?
	  sudo sed -i '/HiddenServiceVersion 3/a HiddenServicePort 22 127.0.0.1:22' /etc/tor/torrc
	else
	  printf "\n/etc/tor/torrc already updated...\n"
	fi

	sudo systemctl reload tor

	printf "\nDo not share your Tor connection address with anyone!\n\n"
	printf "Be sure to store your Tor connection address in a secure location, e.g., your password manager\n\n"
	printf "Tor connection address: %s\n" "$(sudo cat /var/lib/tor/hidden_service_sshd/hostname)"
	# TODO: If it isn't and they want it to be securely stored then show them how to securely store it
	printf "\n"
        read -p "Is your Tor connection address stored in a secure location? [Y/n] " tor_connection_address_confirmation
        break
        ;;
      [nN][oO]|[nN])
	printf "\nSSH remote access through Tor not enabled\n"
	break
        ;;
      *)
        printf "\nInvalid input...\n"
        ;;
    esac
  done
}

set_up_sudo_session
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
