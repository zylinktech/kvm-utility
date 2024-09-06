#!/bin/bash

# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
  echo "whiptail is not installed. Install it using: sudo apt install whiptail"
  exit 1
fi

# Check if virt-install is installed
if ! command -v virt-install >/dev/null 2>&1; then
  echo "virt-install is not installed. Please install it using: sudo apt install virt-manager"
  exit 1
fi

# Fullscreen window using clear
clear

# Welcome message
whiptail --title "VM Creator Utility" --msgbox "Welcome to the VM Creator Utility. This tool helps you create VMs using KVM easily." 10 60

# Get the VM name
VM_NAME=$(whiptail --inputbox "Enter the name of the VM:" 10 60 --title "VM Name" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Get the amount of RAM
RAM=$(whiptail --inputbox "Enter the amount of RAM (in MB, e.g., 2048 for 2GB):" 10 60 --title "RAM" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Get the number of CPUs
CPU=$(whiptail --inputbox "Enter the number of CPU cores (e.g., 2):" 10 60 --title "CPU Cores" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Get the disk size
DISK_SIZE=$(whiptail --inputbox "Enter the size of the virtual disk (in GB, e.g., 20):" 10 60 --title "Disk Size" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Ask the user to choose between ISO or Network installation
INSTALL_METHOD=$(whiptail --title "Installation Method" --menu "Choose the installation source" 15 60 2 \
  "ISO" "Install from an ISO file" \
  "Network" "Install from a network location" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

if [ "$INSTALL_METHOD" = "ISO" ]; then
  # List of popular desktop and server ISOs for selection
  ISO_URL=$(whiptail --title "Choose ISO" --menu "Select an ISO to install the VM" 20 78 15 \
  "Ubuntu Desktop 22.04" "https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso" \
  "Ubuntu Server 22.04" "https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso" \
  "Linux Mint 21" "https://mirrors.edge.kernel.org/linuxmint/stable/21/linuxmint-21-cinnamon-64bit.iso" \
  "Kali Linux 2023.1" "https://cdimage.kali.org/kali-2023.1/kali-linux-2023.1-live-amd64.iso" \
  "Ubuntu Desktop 20.04" "https://releases.ubuntu.com/20.04/ubuntu-20.04.4-desktop-amd64.iso" \
  "Ubuntu Server 20.04" "https://releases.ubuntu.com/20.04/ubuntu-20.04.4-live-server-amd64.iso" \
  "Debian 11" "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.5.0-amd64-netinst.iso" \
  "CentOS 8 Stream" "http://mirror.centos.org/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20220616-dvd1.iso" \
  "Fedora 36 Workstation" "https://download.fedoraproject.org/pub/fedora/linux/releases/36/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-36-1.5.iso" \
  "Fedora 36 Server" "https://download.fedoraproject.org/pub/fedora/linux/releases/36/Server/x86_64/iso/Fedora-Server-netinst-x86_64-36-1.5.iso" \
  "Alpine Linux 3.16" "https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86_64/alpine-standard-3.16.0-x86_64.iso" \
  "Arch Linux" "https://mirror.rackspace.com/archlinux/iso/latest/archlinux-2023.01.01-x86_64.iso" \
  3>&1 1>&2 2>&3)

  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
  INSTALL_FLAG="--cdrom $ISO_URL"
elif [ "$INSTALL_METHOD" = "Network" ]; then
  # Use network-based installation (Ubuntu Focal example)
  INSTALL_LOCATION="http://ftp.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/"
  INSTALL_FLAG="--location $INSTALL_LOCATION"
fi

# Get the OS variant
OS_VARIANT=$(whiptail --inputbox "Enter the OS variant (e.g., ubuntu20.04):" 10 60 --title "OS Variant" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Confirm the details
CONFIRM=$(whiptail --title "Confirmation" --yesno "You've entered the following details:\n\nVM Name: $VM_NAME\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nOS Variant: $OS_VARIANT\n\nDo you want to proceed?" 20 60)

if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Create the VM using virt-install
whiptail --infobox "Creating the VM $VM_NAME. Please wait..." 10 60

sudo virt-install \
  --name "$VM_NAME" \
  --ram "$RAM" \
  --vcpus "$CPU" \
  --disk size="$DISK_SIZE",format=qcow2 \
  --os-variant "$OS_VARIANT" \
  --network network=default \
  --graphics vnc \
  --console pty,target_type=serial \
  $INSTALL_FLAG

# Check if the VM creation was successful
if [ $? -eq 0 ]; then
  whiptail --title "Success" --msgbox "VM $VM_NAME created successfully!" 10 60

  # Fetch the IP address of the VM
  IP_ADDR=$(sudo virsh domifaddr "$VM_NAME" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)

  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="Not available (VM might be starting up or network configuration isn't complete)"
  fi

  # Display the hostname and IP address
  whiptail --title "VM Details" --msgbox "VM Name: $VM_NAME\nHostname: $VM_NAME\nIP Address: $IP_ADDR" 12 60

else
  whiptail --title "Error" --msgbox "Failed to create VM $VM_NAME." 10 60
fi
