#!/bin/bash

ISO_LIST_FILE="os-types"

# Check if the ISO list file exists
if [[ ! -f "$ISO_LIST_FILE" ]]; then
  echo "ISO list file $ISO_LIST_FILE not found. Please create the file with the ISO links."
  exit 1
fi

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

# Prompt the user for a search term
SEARCH_TERM=$(whiptail --inputbox "Enter a search term to filter ISO options (e.g., Ubuntu, Server, Fedora):" 10 60 3>&1 1>&2 2>&3)

# If user cancels the search
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Check if search term is empty
if [[ -z "$SEARCH_TERM" ]]; then
  echo "No search term provided. VM creation canceled."
  exit 1
fi

# Filter the ISO list based on the search term
ISO_MENU=""
while IFS="|" read -r OPTION_NUMBER DESCRIPTION URL; do
  if echo "$DESCRIPTION" | grep -iq "$SEARCH_TERM"; then
    ISO_MENU+="$OPTION_NUMBER \"$DESCRIPTION\" "
  fi
done < "$ISO_LIST_FILE"

# Check if there are any matching results
if [[ -z "$ISO_MENU" ]]; then
  whiptail --title "No Results" --msgbox "No ISOs matched your search term '$SEARCH_TERM'." 10 60
  exit 1
fi

# Set the menu height dynamically based on the number of options
ISO_MENU_HEIGHT=$(echo "$ISO_MENU" | wc -l)

# Show filtered ISO selection menu
ISO_CHOICE=$(eval whiptail --title '"Choose OS ISO"' --menu '"Select the operating system to install:"' $ISO_MENU_HEIGHT 60 $ISO_MENU_HEIGHT $ISO_MENU 3>&1 1>&2 2>&3)

# If user cancels the menu, exit the script
if [ $? -ne 0 ]; then
  echo "VM creation canceled."
  exit 1
fi

# Determine the ISO URL based on the selected option
ISO_URL=$(awk -F'|' -v choice="$ISO_CHOICE" '$1 == choice { print $3 }' "$ISO_LIST_FILE")

# Make sure we have a valid ISO URL
if [[ -z "$ISO_URL" ]]; then
  whiptail --title "Error" --msgbox "Invalid ISO selection. VM creation canceled." 8 60
  exit 1
fi

# Proceed with the rest of the VM creation process (prompting for VM Name, RAM, etc.)
CONFIG_OPTIONS=$(whiptail --title "VM Configuration Menu" --checklist \
"Select the configuration options you want to set:" 20 60 10 \
"VM Name" "Set the name of the VM." ON \
"Hostname" "Set the hostname for the VM." ON \
"RAM" "Set the RAM size for the VM." ON \
"CPU Cores" "Set the number of CPU cores." ON \
"Disk Size" "Set the disk size (GB)." ON 3>&1 1>&2 2>&3)

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

# Make sure mandatory fields are filled
if [[ -z "$VM_NAME" ]]; then
  whiptail --title "Error" --msgbox "VM Name is required. VM creation canceled." 8 60
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
