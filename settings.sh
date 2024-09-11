#!/bin/bash

LOG_FILE="/var/log/kvm-utility.log"

# Function to log messages
log() {
    echo "$(date) - $1" >> "$LOG_FILE"
}

# Function to get the invoking user's home directory (not root)
get_home_directory() {
    if [ -n "$SUDO_USER" ]; then
        eval echo "~$SUDO_USER"
    else
        eval echo "~$USER"
    fi
}

# Function to view VM network settings
view_network_settings() {
    vm_name="$1"
    network_info=$(sudo virsh domiflist "$vm_name")

    whiptail --title "Network Settings: $vm_name" --msgbox "$network_info" 15 60
}

# Function to display VM information
view_vm_information() {
    vm_name="$1"
    vm_info=$(sudo virsh dominfo "$vm_name")

    # Check for VM autostart and protection status
    autostart=$(sudo virsh dominfo "$vm_name" | grep -i "Autostart" | awk '{print $2}')
    is_protected=$(sudo virsh dumpxml "$vm_name" | grep -i "<protected>" | awk -F'[><]' '{print $3}')
    
    # Modify options for autostart and protection checkboxes
    vm_info+="\nAutostart: $autostart"
    vm_info+="\nProtected: ${is_protected:-No}"

    whiptail --title "VM Information: $vm_name" --msgbox "$vm_info" 15 60

    # Ask user if they want to modify autostart or protected status
    OPTIONS=$(whiptail --title "VM Options" --checklist "Modify VM options:" 20 60 10 \
    "Autostart" "Enable/Disable Autostart" "$autostart" \
    "Protected" "Enable/Disable VM Protection" "${is_protected:-OFF}" 3>&1 1>&2 2>&3)

    if [[ "$OPTIONS" == *"Autostart"* ]]; then
        if [[ "$autostart" == "on" ]]; then
            sudo virsh autostart --disable "$vm_name"
        else
            sudo virsh autostart "$vm_name"
        fi
        log "VM $vm_name autostart modified."
    fi

    if [[ "$OPTIONS" == *"Protected"* ]]; then
        if [[ "$is_protected" == "Yes" ]]; then
            sudo virsh edit "$vm_name" --remove "<protected/>"
        else
            sudo virsh edit "$vm_name" --add "<protected/>"
        fi
        log "VM $vm_name protection status modified."
    fi
}

# Function to edit virbr0 network to use the same subnet as the host
edit_virbr0_network() {
    # Get the host network configuration
    host_interface=$(ip route | grep default | awk '{print $5}')
    host_ip=$(ip -o -f inet addr show "$host_interface" | awk '{print $4}')
    host_gateway=$(ip route | grep default | awk '{print $3}')
    host_subnet=$(ip -o -f inet addr show "$host_interface" | awk '{print $4}')

    # Edit virbr0 settings to match the host network
    sudo virsh net-destroy default
    sudo virsh net-edit default

    cat <<EOL | sudo tee /etc/libvirt/qemu/networks/default.xml
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='$host_ip' netmask='$host_subnet'>
    <dhcp>
      <range start='${host_ip%.*}.100' end='${host_ip%.*}.200'/>
    </dhcp>
  </ip>
</network>
EOL

    sudo virsh net-start default
    sudo virsh net-autostart default

    whiptail --title "Success" --msgbox "virbr0 edited to match the host's network configuration." 10 60
    log "virbr0 edited to use the same subnet as the host."
}

# Function to create a network bridge using the selected physical interface
create_bridge() {
    bridge_name=$(whiptail --inputbox "Enter the bridge name (e.g., br0):" 10 60 "br0" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$bridge_name" ]; then
        echo "Operation canceled or invalid bridge name."
        log "Operation canceled or invalid bridge name."
        return
    fi

    selected_iface=$(scan_physical_interfaces)

    ip_addr=$(ip -o -f inet addr show "$selected_iface" | awk '{print $4}')
    gateway=$(ip route | grep "$selected_iface" | grep default | awk '{print $3}')
    subnet=$(ip -o -f inet addr show "$selected_iface" | awk '{print $4}')

    if [ -z "$ip_addr" ] || [ -z "$gateway" ] || [ -z "$subnet" ]; then
        whiptail --title "Error" --msgbox "Failed to retrieve IP configuration for interface $selected_iface." 10 60
        log "Failed to retrieve IP configuration for interface $selected_iface."
        return
    fi

    sudo nmcli connection add type bridge con-name "$bridge_name" ifname "$bridge_name"
    sudo nmcli connection add type bridge-slave ifname "$selected_iface" master "$bridge_name"
    sudo nmcli connection modify "$bridge_name" ipv4.addresses "$ip_addr"
    sudo nmcli connection modify "$bridge_name" ipv4.gateway "$gateway"
    sudo nmcli connection modify "$bridge_name" ipv4.method manual
    sudo nmcli connection up "$bridge_name"

    whiptail --title "Success" --msgbox "Bridge $bridge_name created and connected to interface $selected_iface." 10 60
    log "Bridge $bridge_name created with physical interface $selected_iface."
}

# Function to manage VMs (start, stop, restart, delete, attach/detach interfaces, view network settings, view VM information)
manage_vm() {
    available_vms=$(sudo virsh list --all | awk 'NR>2 {print $2}')

    if [ -z "$available_vms" ]; then
        whiptail --title "Error" --msgbox "No VMs available." 10 60
        return
    fi

    vm_options=()
    for vm in $available_vms; do
        vm_options+=("$vm" "$vm")
    done

    selected_vm=$(whiptail --title "VM Management" --menu "Select a VM to manage:" 15 60 5 "${vm_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    vm_action=$(whiptail --title "Manage VM" --menu "Choose an action for VM $selected_vm:" 15 60 8 \
    "1" "Start VM" \
    "2" "Stop VM" \
    "3" "Restart VM" \
    "4" "Delete VM" \
    "5" "Attach Network Interface" \
    "6" "Detach Network Interface" \
    "7" "View Network Settings" \
    "8" "View VM Information" 3>&1 1>&2 2>&3)

    case "$vm_action" in
        1) sudo virsh start "$selected_vm"; log "VM $selected_vm started." ;;
        2) sudo virsh shutdown "$selected_vm"; log "VM $selected_vm stopped." ;;
        3) sudo virsh reboot "$selected_vm"; log "VM $selected_vm restarted." ;;
        4) sudo virsh destroy "$selected_vm"; sudo virsh undefine "$selected_vm"; log "VM $selected_vm deleted." ;;
        5) attach_network_interface "$selected_vm" ;;
        6) detach_network_interface "$selected_vm" ;;
        7) view_network_settings "$selected_vm" ;;
        8) view_vm_information "$selected_vm" ;;
        *) echo "Invalid option." ;;
    esac
}

# Function to attach a network interface to a VM
attach_network_interface() {
    available_interfaces=$(ip link show | grep -oP '^\d+: \K\w+')

    if [ -z "$available_interfaces" ]; then
        whiptail --title "Error" --msgbox "No available interfaces found to attach." 10 60
        return
    fi

    interface_options=()
    for iface in $available_interfaces; do
        interface_options+=("$iface" "$iface")
    done

    selected_interface=$(whiptail --title "Attach Network Interface" --menu "Select an interface to attach:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$selected_interface" ]; then
        echo "Operation canceled or invalid interface."
        return
    fi

    sudo virsh attach-interface --domain "$1" --type bridge --source "$selected_interface" --model virtio --config --live
    log "Network interface $selected_interface attached to VM $1."
}

# Function to detach a network interface from a VM
detach_network_interface() {
    interfaces=$(sudo virsh domiflist "$1" | awk 'NR>2 {print $1, $5}')
    
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No network interfaces found for VM $1." 10 60
        return
    fi

    interface_options=()
    while read -r line; do
        iface_name=$(echo "$line" | awk '{print $1}')
        iface_mac=$(echo "$line" | awk '{print $2}')
        interface_options+=("$iface_mac" "$iface_name")
    done <<< "$interfaces"

    selected_iface_mac=$(whiptail --title "Detach Network Interface" --menu "Select an interface to detach from VM $1:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    sudo virsh detach-interface "$1" bridge --mac "$selected_iface_mac" --config --live
    log "Network interface detached from VM $1."
}

# Main menu loop
while true; do
    ACTION=$(whiptail --title "KVM Utility Settings" --menu "Choose an action:" 15 60 4 \
    "1" "Network Management" \
    "2" "Storage Management" \
    "3" "VM Management" \
    "4" "Exit" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        log "Main menu canceled."
        echo "Main menu canceled."
        exit 0
    fi

    case "$ACTION" in
        1)
            NETWORK_ACTION=$(whiptail --title "Network Management" --menu "Choose an action:" 15 60 5 \
            "1" "Create Network Bridge" \
            "2" "Create Virtual Network (vnet)" \
            "3" "Edit virbr0 to match host network" \
            "4" "Delete Network Interface" \
            "5" "Back" 3>&1 1>&2 2>&3)

            case "$NETWORK_ACTION" in
                1) create_bridge ;;
                2) create_vnet ;;
                3) edit_virbr0_network ;;
                4) delete_network_interface ;;
                5) continue ;;
                *) echo "Invalid option." ;;
            esac
        ;;
        2)
            STORAGE_ACTION=$(whiptail --title "Storage Management" --menu "Choose an action:" 15 60 3 \
            "1" "Create Storage Pool" \
            "2" "Delete Storage Pool" \
            "3" "List Storage Pools" \
            "4" "Back" 3>&1 1>&2 2>&3)

            case "$STORAGE_ACTION" in
                1) create_pool ;;
                2) delete_pool ;;
                3) list_storage_pools ;;
                4) continue ;;
                *) echo "Invalid option." ;;
            esac
        ;;
        3) manage_vm ;;
        4) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
