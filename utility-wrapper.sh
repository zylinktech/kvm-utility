#!/bin/bash

# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
  echo "whiptail is not installed. Install it using: sudo apt install whiptail"
  exit 1
fi

# Check if virt-install is installed
if ! command -v virt-install >/dev/null 2>&1; then
  echo "virt-install is not installed. Install it using: sudo apt install virt-manager"
  exit 1
fi

# Fullscreen window using clear
clear

# Menu to let user select what they want to configure
CONFIG_OPTIONS=$(whiptail --title "VM Configuration Menu" --checklist \
"Select the configuration options you want to set:" 20 60 10 \
"VM Name" "Set the name of the VM." ON \
"Hostname" "Set the hostname for the VM." ON \
"RAM" "Set the RAM size for the VM." ON \
"CPU Cores" "Set the number of CPU cores." ON \
"Disk Size" "Set the disk size (GB)." ON \
"ISO" "Choose an ISO image for installation." ON 3>&1 1>&2 2>&3)

# If user cancels the menu
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Default values if not selected
VM_NAME=""
HOSTNAME=""
RAM="2048"
CPU="2"
DISK_SIZE="20"
ISO_URL=""

# Configure based on user selection
if [[ $CONFIG_OPTIONS == *"VM Name"* ]]; then
  VM_NAME=$(whiptail --inputbox "Enter the VM name:" 10 60 3>&1 1>&2 2>&3)
fi

if [[ $CONFIG_OPTIONS == *"Hostname"* ]]; then
  HOSTNAME=$(whiptail --inputbox "Enter the Hostname:" 10 60 3>&1 1>&2 2>&3)
fi

if [[ $CONFIG_OPTIONS == *"RAM"* ]]; then
  RAM=$(whiptail --inputbox "Enter the RAM size (in MB):" 10 60 "2048" 3>&1 1>&2 2>&3)
fi

if [[ $CONFIG_OPTIONS == *"CPU Cores"* ]]; then
  CPU=$(whiptail --inputbox "Enter the number of CPU cores:" 10 60 "2" 3>&1 1>&2 2>&3)
fi

if [[ $CONFIG_OPTIONS == *"Disk Size"* ]]; then
  DISK_SIZE=$(whiptail --inputbox "Enter the Disk size (in GB):" 10 60 "20" 3>&1 1>&2 2>&3)
fi

# ISO selection menu
if [[ $CONFIG_OPTIONS == *"ISO"* ]]; then
  ISO_CHOICE=$(whiptail --title "Choose ISO" --menu "Select the operating system ISO:" 15 60 6 \
  "1" "Ubuntu Desktop 22.04" \
  "2" "Ubuntu Server 22.04" \
  "3" "CentOS 8" \
  "4" "Fedora 36" \
  "5" "Debian 11" \
  "6" "Alpine Linux" 3>&1 1>&2 2>&3)

  case "$ISO_CHOICE" in
    1) ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso" ;;
    2) ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso" ;;
    3) ISO_URL="http://mirror.centos.org/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20220616-dvd1.iso" ;;
    4) ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/36/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-36-1.5.iso" ;;
    5) ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.5.0-amd64-netinst.iso" ;;
    6) ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86_64/alpine-standard-3.16.0-x86_64.iso" ;;
    *) echo "Invalid option. VM creation canceled." ; exit 1 ;;
  esac
fi

# Make sure mandatory fields are filled
if [[ -z "$VM_NAME" || -z "$ISO_URL" ]]; then
  whiptail --title "Error" --msgbox "VM Name and ISO must be selected. VM creation canceled." 8 60
  exit 1
fi

# Confirm the details before proceeding
CONFIRM=$(whiptail --title "Confirmation" --yesno "Confirm VM details:\n\nVM Name: $VM_NAME\nHostname: ${HOSTNAME:-Not set}\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nISO: $ISO_URL\nNetwork: DHCP\n\nDo you want to proceed?" 15 60)

if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Execute the virt-install command to create the VM
sudo virt-install \
  --name "$VM_NAME" \
  --ram "$RAM" \
  --vcpus "$CPU" \
  --disk size="$DISK_SIZE",format=qcow2 \
  --cdrom "$ISO_URL" \
  --network network=default \
  --os-variant ubuntu20.04 \
  --graphics vnc \
  --console pty,target_type=serial \
  --hostname "$HOSTNAME"

# Check if the VM creation was successful and fetch the IP address
if [ $? -eq 0 ]; then
  IP_ADDR=$(sudo virsh domifaddr "$VM_NAME" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="Not available (VM might be starting up)"
  fi
  whiptail --title "Success" --msgbox "VM $VM_NAME created successfully!\n\nHostname: ${HOSTNAME:-Not set}\nIP Address: $IP_ADDR" 10 60
else
  whiptail --title "Error" --msgbox "Failed to create VM $VM_NAME." 10 60
fi
