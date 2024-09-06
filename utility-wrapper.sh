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

# Show a dropdown menu to select the VM OS/ISO source
OS_CHOICE=$(whiptail --title "Choose OS ISO" --menu "Select the operating system to install:" 15 60 6 \
"1" "Ubuntu Desktop 22.04" \
"2" "Ubuntu Server 22.04" \
"3" "CentOS 8" \
"4" "Fedora 36" \
"5" "Debian 11" \
"6" "Alpine Linux" 3>&1 1>&2 2>&3)

# If the user cancels the menu, exit the script
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Determine the ISO URL based on the selected option
case "$OS_CHOICE" in
  1) ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso" ;;
  2) ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso" ;;
  3) ISO_URL="http://mirror.centos.org/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20220616-dvd1.iso" ;;
  4) ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/36/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-36-1.5.iso" ;;
  5) ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.5.0-amd64-netinst.iso" ;;
  6) ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86_64/alpine-standard-3.16.0-x86_64.iso" ;;
  *) echo "Invalid option. VM creation canceled." ; exit 1 ;;
esac

# Now, proceed with gathering other details
FORM_OUTPUT=$(whiptail --title "Zylinktech VM Creation Utility" --form "Setup" 20 60 10 \
"VM Name:" 1 1 "" 1 25 25 0 \
"RAM (MB):" 2 1 "2048" 2 25 25 0 \
"CPU Cores:" 3 1 "2" 3 25 25 0 \
"Disk Size (GB):" 4 1 "20" 4 25 25 0 3>&1 1>&2 2>&3)

# If the user cancels the form, exit the script
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Read the form output into separate variables
IFS=$'\n' read -r VM_NAME RAM CPU DISK_SIZE <<< "$FORM_OUTPUT"

# Validate required fields
if [[ -z "$VM_NAME" || -z "$RAM" || -z "$CPU" || -z "$DISK_SIZE" ]]; then
  whiptail --title "Error" --msgbox "One or more required fields are missing. VM creation canceled." 8 60
  exit 1
fi

# Print the values to ensure we captured them correctly (debugging)
echo "VM Name: $VM_NAME"
echo "RAM: $RAM MB"
echo "CPU Cores: $CPU"
echo "Disk Size: $DISK_SIZE GB"
echo "ISO URL: $ISO_URL"

# Confirm the details before proceeding
CONFIRM=$(whiptail --title "Confirmation" --yesno "Confirm VM details:\n\nVM Name: $VM_NAME\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nISO: $ISO_URL\nNetwork: DHCP\n\nDo you want to proceed?" 15 60)

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
  --console pty,target_type=serial

# Check if the VM creation was successful and fetch the IP address
if [ $? -eq 0 ]; then
  IP_ADDR=$(sudo virsh domifaddr "$VM_NAME" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="Not available (VM might be starting up)"
  fi
  whiptail --title "Success" --msgbox "VM $VM_NAME created successfully!\n\nIP Address: $IP_ADDR" 10 60
else
  whiptail --title "Error" --msgbox "Failed to create VM $VM_NAME." 10 60
fi
