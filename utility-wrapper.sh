#!/bin/bash

ISO_LIST_FILE="/usr/local/bin/os-types"
LOG_FILE="/var/log/kvm-utility.log"

# Logging function
log() {
  echo "$(date) - $1" >> "$LOG_FILE"
}

# Get storage pool path
vm_directory=$(virsh pool-dumpxml custompool | grep -oP '(?<=<path>).*?(?=</path>)')

# Fullscreen window using clear
clear

# Loop until a valid ISO is selected or process is canceled
while true; do
  SEARCH_TERM=$(whiptail --inputbox "Search ISO (leave blank to show all):" 10 60 3>&1 1>&2 2>&3)

  if [ $? -ne 0 ]; then
    log "VM creation canceled during ISO search."
    echo "VM creation canceled."
    exit 1
  fi

  ISO_ARRAY=()
  if [[ -z "$SEARCH_TERM" ]]; then
    while IFS="|" read -r OPTION_NUMBER DESCRIPTION URL; do
      ISO_ARRAY+=("$DESCRIPTION|$URL")
    done < "$ISO_LIST_FILE"
  else
    while IFS="|" read -r OPTION_NUMBER DESCRIPTION URL; do
      if echo "$DESCRIPTION" | grep -iq "$SEARCH_TERM"; then
        ISO_ARRAY+=("$DESCRIPTION|$URL")
      fi
    done < "$ISO_LIST_FILE"
  fi

  if [[ ${#ISO_ARRAY[@]} -eq 0 ]]; then
    whiptail --title "No Results" --msgbox "No ISOs matched your search term '$SEARCH_TERM'." 10 60
    continue
  fi

  PAGE_SIZE=5
  PAGE=1
  TOTAL_PAGES=$(( (${#ISO_ARRAY[@]} + PAGE_SIZE - 1) / PAGE_SIZE ))

  while true; do
    START=$(( (PAGE - 1) * PAGE_SIZE ))
    END=$(( START + PAGE_SIZE - 1 ))
    [ $END -ge ${#ISO_ARRAY[@]} ] && END=$((${#ISO_ARRAY[@]} - 1))

    ISO_MENU=""
    COUNT=1
    for i in $(seq $START $END); do
      ISO_DESC=$(echo "${ISO_ARRAY[$i]}" | cut -d'|' -f1)
      ISO_MENU+="$COUNT \"$ISO_DESC\" "
      COUNT=$((COUNT + 1))
    done

    [ $PAGE -gt 1 ] && ISO_MENU+="Previous \"Previous Page\" "
    [ $PAGE -lt $TOTAL_PAGES ] && ISO_MENU+="Next \"Next Page\" "

    ISO_CHOICE=$(eval whiptail --title '"Choose Guest OS"' --menu '"Select the operating system to install:"' 15 60 10 $ISO_MENU 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
      log "VM creation canceled during ISO selection."
      echo "VM creation canceled."
      exit 1
    fi

    if [[ "$ISO_CHOICE" == "Next" ]]; then
      PAGE=$((PAGE + 1))
      continue
    elif [[ "$ISO_CHOICE" == "Previous" ]]; then
      PAGE=$((PAGE - 1))
      continue
    fi

    SELECTED_INDEX=$(( (PAGE - 1) * PAGE_SIZE + ISO_CHOICE - 1 ))
    ISO_URL=$(echo "${ISO_ARRAY[$SELECTED_INDEX]}" | cut -d'|' -f2)
    ISO_NAME=$(basename "$ISO_URL")

    ACTION=$(whiptail --title "Confirm selection" --menu "Select an option" 15 60 3 \
    "Proceed" "Proceed with this ISO" \
    "Go Back" "Search again or change ISO" \
    "Cancel" "Cancel the VM creation" 3>&1 1>&2 2>&3)

    case "$ACTION" in
      "Proceed")
        log "ISO selected: $ISO_NAME"
        break 2
        ;;
      "Go Back")
        break
        ;;
      "Cancel")
        log "VM creation canceled after ISO selection."
        echo "VM creation canceled."
        exit 1
        ;;
    esac
  done
done

# Proceed with VM creation
CONFIG_OPTIONS=$(whiptail --title "zylinktech kvm utility" --checklist \
"Configure:" 20 60 10 \
"VM Name" "Set the name of the VM." ON \
"RAM" "Set the RAM size for the VM. (MB)" ON \
"CPU Cores" "Set the number of CPU cores." ON \
"Disk Size" "Set the disk size (GB)." ON 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then
  log "VM creation canceled during configuration."
  echo "VM creation canceled."
  exit 1
fi

VM_NAME=""
RAM="2048"
CPU="2"
DISK_SIZE="16"

if [[ $CONFIG_OPTIONS == *"VM Name"* ]]; then
  VM_NAME=$(whiptail --inputbox "Enter the VM name:" 10 60 3>&1 1>&2 2>&3)
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

if [[ -z "$VM_NAME" ]]; then
  log "VM creation failed: No VM name provided."
  whiptail --title "Error" --msgbox "VM Name is required. Exiting." 8 60
  exit 1
fi

CONFIRM=$(whiptail --title "Confirmation" --yesno "Confirm VM details:\n\nVM Name: $VM_NAME\nRAM: ${RAM}MB\nCPU Cores: $CPU\nDisk Size: ${DISK_SIZE}GB\nISO: $ISO_URL\nNetwork: DHCP\n\nDo you want to proceed?" 15 60)

if [ $? -ne 0 ]; then
  log "VM creation canceled after confirmation."
  echo "VM creation canceled."
  exit 1
fi

# Attempt VM creation and log success or error
sudo virt-install \
  --name "$VM_NAME" \
  --ram "$RAM" \
  --vcpus "$CPU" \
  --disk path="$vm_directory/$VM_NAME.qcow2",size="$DISK_SIZE",format=qcow2 \
  --cdrom "$ISO_URL" \
  --network network=default,model=virtio \
  --os-variant ubuntu20.04 \
  --graphics vnc \
  --console pty,target_type=serial \
  --check disk_size=off 2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
  log "VM $VM_NAME created successfully."
  IP_ADDR=$(sudo virsh domifaddr "$VM_NAME" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
  [ -z "$IP_ADDR" ] && IP_ADDR="Not available (VM might be starting up)"
  whiptail --title "Success" --msgbox "VM $VM_NAME created successfully!\n\nIP Address: $IP_ADDR" 10 60
else
  log "Failed to create VM $VM_NAME."
  whiptail --title "Error" --msgbox "Failed to create VM $VM_NAME. Check the log file at $LOG_FILE for details." 10 60
fi
