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

# Function to set a static IP configuration
set_static_ip() {
  IP_ADDR=$(whiptail --inputbox "Enter the static IP address (e.g., 192.168.1.100):" 10 60 --title "Static IP Address" 3>&1 1>&2 2>&3)
  SUBNET_MASK=$(whiptail --inputbox "Enter the subnet mask (e.g., 255.255.255.0):" 10 60 --title "Subnet Mask" 3>&1 1>&2 2>&3)
  GATEWAY=$(whiptail --inputbox "Enter the gateway IP address (e.g., 192.168.1.1):" 10 60 --title "Gateway IP Address" 3>&1 1>&2 2>&3)
  
  # Return the configuration as a network argument for virt-install
  NETWORK_CONFIG="--network network=default,model=virtio,mac=RANDOM,ip=$IP_ADDR/$SUBNET_MASK,gateway=$GATEWAY"
}

# Display the main menu
CHOICES=$(whiptail --title "VM Creator Utility" --checklist \
"Select options to configure the VM:" 20 60 10 \
"VM Name" "Enter the name of the VM." ON \
"RAM" "Specify the amount of RAM (in MB)." ON \
"CPU" "Specify the number of CPU cores." ON \
"Disk Size" "Specify the size of the disk (in GB)." ON \
"ISO" "Choose an ISO to install the VM." ON \
"Static IP" "Set a static IP address for the VM." OFF 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Gather input for selected options
if [[ $CHOICES == *"VM Name"* ]]; then
  VM_NAME=$(whiptail --inputbox "Enter the name of the VM:" 10 60 --title "VM Name" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
fi

if [[ $CHOICES == *"RAM"* ]]; then
  RAM=$(whiptail --inputbox "Enter the amount of RAM (in MB, e.g., 2048):" 10 60 --title "RAM" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
fi

if [[ $CHOICES == *"CPU"* ]]; then
  CPU=$(whiptail --inputbox "Enter the number of CPU cores (e.g., 2):" 10 60 --title "CPU Cores" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
fi

if [[ $CHOICES == *"Disk Size"* ]]; then
  DISK_SIZE=$(whiptail --inputbox "Enter the size of the disk (in GB, e.g., 20):" 10 60 --title "Disk Size" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
fi

if [[ $CHOICES == *"ISO"* ]]; then
  ISO_URL=$(whiptail --title "Choose ISO" --menu "Select an ISO to install the VM:" 20 60 10 \
  "Ubuntu Desktop 22.04" "https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso" \
  "Ubuntu Server 22.04" "https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso" \
  "Linux Mint 21" "https://mirrors.edge.kernel.org/linuxmint/stable/21/linuxmint-21-cinnamon-64bit.iso" \
  "Kali Linux 2023.1" "https://cdimage.kali.org/kali-2023.1/kali-linux-2023.1-live-amd64.iso" \
  3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi
fi

if [[ $CHOICES == *"Static IP"* ]]; then
  set_static_ip
fi

# Confirm the details
CONFIRM=$(whiptail --title "Confirmation" --yesno "You've entered the following details:\n\nVM Name: $VM_NAME\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nISO URL: $ISO_URL\nStatic IP: ${IP_ADDR:-DHCP}\n\nDo you want to proceed?" 20 60)
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Create the VM using virt-install
sudo virt-install \
  --name "$VM_NAME" \
  --ram "$RAM" \
  --vcpus "$CPU" \
  --disk size="$DISK_SIZE",format=qcow2 \
  --cdrom "$ISO_URL" \
  ${NETWORK_CONFIG:-"--network network=default"} \
  --os-variant ubuntu20.04 \
  --graphics vnc \
  --console pty,target_type=serial

# Check if the VM creation was successful
if [ $? -eq 0 ]; then
  IP_ADDR=$(sudo virsh domifaddr "$VM_NAME" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="Not available (VM might be starting up)"
  fi
  whiptail --title "Success" --msgbox "VM $VM_NAME created successfully!\n\nIP Address: $IP_ADDR" 10 60
else
  whiptail --title "Error" --msgbox "Failed to create VM $VM_NAME." 10 60
fi
