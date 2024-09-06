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

# Show a single form where users can input all options in one go
FORM_OUTPUT=$(whiptail --title "zylinktech virtual machine utility" --form "VM Setup:" 20 60 10 \
"VM Name:" 1 1 "" 1 25 25 0 \
"RAM (MB):" 2 1 "2048" 2 25 25 0 \
"CPU Cores:" 3 1 "2" 3 25 25 0 \
"Disk Size (GB):" 4 1 "20" 4 25 25 0 \
"ISO URL:" 5 1 "https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso" 5 25 60 0 \
"Static IP (Optional):" 6 1 "" 6 25 25 0 \
"Subnet Mask (Optional):" 7 1 "" 7 25 25 0 \
"Gateway IP (Optional):" 8 1 "" 8 25 25 0 3>&1 1>&2 2>&3)

# If the user cancels the form
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Debugging: Print the parsed form values
echo "$FORM_OUTPUT" | while read -r line; do echo "Form Value: $line"; done

# Parse form output
VM_NAME=$(echo "$FORM_OUTPUT" | sed -n '1p')
RAM=$(echo "$FORM_OUTPUT" | sed -n '2p')
CPU=$(echo "$FORM_OUTPUT" | sed -n '3p')
DISK_SIZE=$(echo "$FORM_OUTPUT" | sed -n '4p')
ISO_URL=$(echo "$FORM_OUTPUT" | sed -n '5p')
STATIC_IP=$(echo "$FORM_OUTPUT" | sed -n '6p')
SUBNET_MASK=$(echo "$FORM_OUTPUT" | sed -n '7p')
GATEWAY=$(echo "$FORM_OUTPUT" | sed -n '8p')

# Debugging: Print parsed variables
echo "VM Name: $VM_NAME"
echo "RAM: $RAM MB"
echo "CPU Cores: $CPU"
echo "Disk Size: $DISK_SIZE GB"
echo "ISO URL: $ISO_URL"
echo "Static IP: $STATIC_IP"
echo "Subnet Mask: $SUBNET_MASK"
echo "Gateway IP: $GATEWAY"

# If static IP details were entered, configure the network with a static IP
if [ -n "$STATIC_IP" ] && [ -n "$SUBNET_MASK" ] && [ -n "$GATEWAY" ]; then
  NETWORK_CONFIG="--network network=default,model=virtio,mac=RANDOM,ip=$STATIC_IP/$SUBNET_MASK,gateway=$GATEWAY"
else
  NETWORK_CONFIG="--network network=default"
fi

# Confirm the details
CONFIRM=$(whiptail --title "Confirmation" --yesno "Confirm details:\n\nVM Name: $VM_NAME\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nISO URL: $ISO_URL\nStatic IP: ${STATIC_IP:-DHCP}\n\nDo you want to proceed?" 20 60)
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
  $NETWORK_CONFIG \
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
