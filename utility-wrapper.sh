#!/bin/bash

ISO_LIST_FILE="os-types"
ISO_SAVE_DIR="/var/lib/libvirt/images/isos/"

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

# Loop until user successfully selects an ISO or cancels
while true; do
  # Prompt the user for a search term
  SEARCH_TERM=$(whiptail --inputbox "Enter a search term to filter ISO options (leave blank to show all ISOs):" 10 60 3>&1 1>&2 2>&3)

  # If user cancels the search
  if [ $? -ne 0 ]; then
    echo "VM creation canceled."
    exit 1
  fi

  # Load the entire ISO list if no search term is provided
  ISO_ARRAY=()
  if [[ -z "$SEARCH_TERM" ]]; then
    # No search term provided, load all ISOs
    while IFS="|" read -r OPTION_NUMBER DESCRIPTION URL; do
      ISO_ARRAY+=("$DESCRIPTION|$URL")
    done < "$ISO_LIST_FILE"
  else
    # Filter the ISO list based on the search term
    while IFS="|" read -r OPTION_NUMBER DESCRIPTION URL; do
      if echo "$DESCRIPTION" | grep -iq "$SEARCH_TERM"; then
        ISO_ARRAY+=("$DESCRIPTION|$URL")
      fi
    done < "$ISO_LIST_FILE"
  fi

  # Check if there are any matching results
  if [[ ${#ISO_ARRAY[@]} -eq 0 ]]; then
    whiptail --title "No Results" --msgbox "No ISOs matched your search term '$SEARCH_TERM'." 10 60
    continue
  fi

  # Pagination variables
  PAGE_SIZE=5
  PAGE=1
  TOTAL_PAGES=$(( (${#ISO_ARRAY[@]} + PAGE_SIZE - 1) / PAGE_SIZE ))

  while true; do
    # Calculate the start and end indices for the current page
    START=$(( (PAGE - 1) * PAGE_SIZE ))
    END=$(( START + PAGE_SIZE - 1 ))
    if [[ $END -ge ${#ISO_ARRAY[@]} ]]; then
      END=$((${#ISO_ARRAY[@]} - 1))
    fi

    # Generate the menu for the current page
    ISO_MENU=""
    COUNT=1
    for i in $(seq $START $END); do
      ISO_DESC=$(echo "${ISO_ARRAY[$i]}" | cut -d'|' -f1)
      ISO_MENU+="$COUNT \"$ISO_DESC\" "
      COUNT=$((COUNT + 1))
    done

    # Add navigation options
    if [[ $PAGE -gt 1 ]]; then
      ISO_MENU+="Previous \"Previous Page\" "
    fi
    if [[ $PAGE -lt $TOTAL_PAGES ]]; then
      ISO_MENU+="Next \"Next Page\" "
    fi

    # Set the menu height dynamically based on the number of options
    ISO_MENU_HEIGHT=$((PAGE_SIZE + 3))

    # Show paginated ISO selection menu with numbered options
    ISO_CHOICE=$(eval whiptail --title '"Choose OS ISO"' --menu '"Select the operating system to install:"' $ISO_MENU_HEIGHT 60 $ISO_MENU_HEIGHT $ISO_MENU 3>&1 1>&2 2>&3)

    # If user cancels the menu, exit the script
    if [ $? -ne 0 ]; then
      echo "VM creation canceled."
      exit 1
    fi

    # Handle the user's choice
    if [[ "$ISO_CHOICE" == "Next" ]]; then
      PAGE=$((PAGE + 1))  # Go to the next page
      continue
    elif [[ "$ISO_CHOICE" == "Previous" ]]; then
      PAGE=$((PAGE - 1))  # Go to the previous page
      continue
    fi

    # Determine the selected ISO based on the choice number
    SELECTED_INDEX=$(( (PAGE - 1) * PAGE_SIZE + ISO_CHOICE - 1 ))
    ISO_URL=$(echo "${ISO_ARRAY[$SELECTED_INDEX]}" | cut -d'|' -f2)
    ISO_NAME=$(basename "$ISO_URL")

    # Provide a menu for proceeding or going back
    ACTION=$(whiptail --title "What next?" --menu "Select what you want to do next:" 15 60 3 \
    "Proceed" "Proceed with this ISO" \
    "Go Back" "Search again or change ISO" \
    "Cancel" "Cancel the VM creation" 3>&1 1>&2 2>&3)

    # Handle the actions
    case "$ACTION" in
      "Proceed")
        break 2  # Break out of both loops and proceed with the selected ISO
        ;;
      "Go Back")
        break  # Go back to the search input prompt
        ;;
      "Cancel")
        echo "VM creation canceled."
        exit 1
        ;;
    esac
  done
done

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
