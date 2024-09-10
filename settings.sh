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

# Function to create a storage pool with a default location in the invoking user's home directory and display pool size after creation
create_pool() {
    user_home=$(get_home_directory)
    
    # Provide the default pool directory as ~/VMs
    pool_dir=$(whiptail --inputbox "Enter the directory for the storage pool:" 10 60 "$user_home/VMs" --title "Create Storage Pool" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$pool_dir" ]; then
        echo "Operation canceled or invalid directory."
        log "Operation canceled or invalid directory for storage pool."
        return
    fi

    # Create the directory if it doesn't exist
    if [ ! -d "$pool_dir" ]; then
        mkdir -p "$pool_dir"
        log "Directory $pool_dir created."
    fi

    # Ask for the storage pool name
    pool_name=$(whiptail --inputbox "Enter the name of the new storage pool:" 10 60 "newpool" --title "Create Storage Pool" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$pool_name" ]; then
        echo "Operation canceled or invalid pool name."
        log "Operation canceled or invalid pool name."
        return
    fi

    # Define and start the storage pool
    sudo virsh pool-define-as --name "$pool_name" --type dir --target "$pool_dir"
    if [ $? -eq 0 ]; then
        sudo virsh pool-start "$pool_name"
        sudo virsh pool-autostart "$pool_name"
        log "Storage pool '$pool_name' created at '$pool_dir'."

        pool_info=$(sudo virsh pool-info "$pool_name")
        total_size=$(echo "$pool_info" | grep 'Capacity' | awk '{print $2, $3}')
        free_size=$(echo "$pool_info" | grep 'Available' | awk '{print $2, $3}')
        whiptail --title "Pool Info" --msgbox "Storage pool '$pool_name' created at '$pool_dir'.\nTotal Size: $total_size\nFree Space: $free_size" 10 60
    else
        echo "Failed to define the storage pool."
        log "Failed to define storage pool '$pool_name'."
    fi
}

# Function to delete a virtual machine with error handling
delete_vm() {
    available_vms=$(sudo virsh list --all | awk 'NR>2 {print $2}')

    if [ -z "$available_vms" ]; then
        whiptail --title "Error" --msgbox "No VMs available to delete." 10 60
        log "No VMs available for deletion."
        return
    fi

    vm_options=()
    for vm in $available_vms; do
        vm_options+=("$vm" "$vm")
    done

    selected_vm=$(whiptail --title "Delete VM" --menu "Select a VM to delete:" 15 60 5 "${vm_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    if sudo virsh dominfo "$selected_vm" >/dev/null 2>&1; then
        # Only try to destroy the VM if it's running
        if sudo virsh domstate "$selected_vm" | grep -q "running"; then
            sudo virsh destroy "$selected_vm"
            log "VM '$selected_vm' destroyed."
        fi
        sudo virsh undefine "$selected_vm" --remove-all-storage
        log "VM '$selected_vm' undefined and deleted."
    else
        echo "VM '$selected_vm' not found."
        log "VM '$selected_vm' not found."
    fi
}

# Function to delete a storage pool with size and usage display
delete_pool() {
    available_pools=$(sudo virsh pool-list --all | awk 'NR>2 {print $1}')

    if [ -z "$available_pools" ]; then
        whiptail --title "Error" --msgbox "No storage pools available to delete." 10 60
        log "No storage pools available for deletion."
        return
    fi

    pool_options=()
    for pool in $available_pools; do
        pool_info=$(sudo virsh pool-info "$pool")
        total_size=$(echo "$pool_info" | grep 'Capacity' | awk '{print $2, $3}')
        free_size=$(echo "$pool_info" | grep 'Available' | awk '{print $2, $3}')
        used_size=$(echo "$total_size - $free_size" | bc)
        pool_options+=("$pool" "($used_size/$total_size Used)")
    done

    selected_pool=$(whiptail --title "Delete Storage Pool" --menu "Select a storage pool to delete:" 15 60 5 "${pool_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    if sudo virsh pool-info "$selected_pool" >/dev/null 2>&1; then
        sudo virsh pool-destroy "$selected_pool"
        sudo virsh pool-undefine "$selected_pool"
        log "Storage pool '$selected_pool' deleted."
    else
        echo "Storage pool '$selected_pool' not found."
        log "Storage pool '$selected_pool' not found."
    fi
}

# Function to display VM Information (status, network, and IP)
vm_information() {
    available_vms=$(sudo virsh list --all | awk 'NR>2 {print $2}')

    if [ -z "$available_vms" ]; then
        whiptail --title "VM Information" --msgbox "No VMs available." 10 60
        log "No VMs available for information display."
        return
    fi

    vm_options=()
    for vm in $available_vms; do
        status=$(sudo virsh domstate "$vm")
        network=$(sudo virsh domiflist "$vm" | awk 'NR>2 {print $3}')
        ip=$(sudo virsh domifaddr "$vm" | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
        vm_options+=("$vm" "Status: $status, Network: $network, IP: ${ip:-Not Available}")
    done

    whiptail --title "VM Information" --menu "Select a VM to view details:" 15 60 5 "${vm_options[@]}" 3>&1 1>&2 2>&3
}

# Function to manage network interfaces (create, delete, or change)
manage_network_interface() {
    ACTION=$(whiptail --title "Network Interface" --menu "Choose an action:" 15 60 4 \
    "1" "Create Network Interface" \
    "2" "Delete Network Interface" \
    "3" "Change Network Interface for a VM" \
    "4" "Back" 3>&1 1>&2 2>&3)

    case "$ACTION" in
        1) create_network_interface ;;
        2) delete_network_interface ;;
        3) change_network_interface ;;
        4) return ;;
    esac
}

# Function to create a network interface (bridge or vnet)
create_network_interface() {
    interface_type=$(whiptail --title "Select Interface Type" --menu "Choose the type of network interface to create:" 15 60 2 \
    "1" "Bridge" \
    "2" "Virtual Network (vnet)" 3>&1 1>&2 2>&3)

    if [ "$interface_type" == "1" ]; then
        bridge_name=$(whiptail --inputbox "Enter the bridge name (e.g., br0):" 10 60 "br0" 3>&1 1>&2 2>&3)
        physical_interface=$(whiptail --inputbox "Enter the physical network interface (e.g., eth0):" 10 60 "eth0" 3>&1 1>&2 2>&3)
        sudo nmcli connection add type bridge con-name "$bridge_name" ifname "$bridge_name"
        sudo nmcli connection add type bridge-slave ifname "$physical_interface" master "$bridge_name"
        sudo nmcli connection modify "$bridge_name" ipv4.method auto
        sudo nmcli connection up "$bridge_name"
        whiptail --title "Success" --msgbox "Bridge $bridge_name created successfully." 10 60
        log "Bridge $bridge_name created with physical interface $physical_interface."

    elif [ "$interface_type" == "2" ]; then
        vnet_name=$(whiptail --inputbox "Enter the virtual network interface name (e.g., vnet0):" 10 60 "vnet0" 3>&1 1>&2 2>&3)
        vnet_xml="/tmp/${vnet_name}.xml"
        sudo bash -c "cat > $vnet_xml" <<EOL
<network>
  <name>$vnet_name</name>
  <bridge name='$vnet_name' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'/>
</network>
EOL
        sudo virsh net-define "$vnet_xml"
        sudo virsh net-start "$vnet_name"
        sudo virsh net-autostart "$vnet_name"
        whiptail --title "Success" --msgbox "Virtual network $vnet_name created successfully." 10 60
        log "Virtual network $vnet_name created."
        rm -f "$vnet_xml"
    fi
}

# Function to delete a network interface
delete_network_interface() {
    interfaces=$(ip link show | grep -oP '^\d+: \K\w+')
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No network interfaces found." 10 60
        return
    fi

    interface_options=()
    for iface in $interfaces; do
        interface_options+=("$iface" "$iface")
    done

    selected_interface=$(whiptail --title "Delete Network Interface" --menu "Select an interface to delete:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    sudo nmcli connection delete "$selected_interface"
    whiptail --title "Success" --msgbox "Network interface $selected_interface deleted successfully." 10 60
}

# Function to change the network interface of a VM
change_network_interface() {
    available_vms=$(sudo virsh list --all | awk 'NR>2 {print $2}')
    if [ -z "$available_vms" ]; then
        whiptail --title "Error" --msgbox "No VMs available." 10 60
        return
    fi

    vm_options=()
    for vm in $available_vms; do
        vm_options+=("$vm" "$vm")
    done

    selected_vm=$(whiptail --title "Change VM Network" --menu "Select a VM to change the network interface:" 15 60 5 "${vm_options[@]}" 3>&1 1>&2 2>&3)

    interfaces=$(ip link show | grep -E '^[0-9]+: br' | awk -F: '{print $2}' | xargs)
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No available bridge interfaces found." 10 60
        return
    fi

    bridge_options=()
    for iface in $interfaces; do
        bridge_options+=("$iface" "$iface")
    done

    selected_bridge=$(whiptail --title "Select Bridge" --menu "Select the bridge interface to assign:" 15 60 5 "${bridge_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    sudo virsh detach-interface "$selected_vm" bridge --current
    sudo virsh attach-interface --domain "$selected_vm" --type bridge --source "$selected_bridge" --model virtio --config --live
    whiptail --title "Success" --msgbox "Network interface of VM $selected_vm changed to $selected_bridge." 10 60
}

# Main menu loop
while true; do
    ACTION=$(whiptail --title "KVM Utility Settings" --menu "Choose an action:" 15 60 6 \
    "1" "Create Storage Pool" \
    "2" "Delete Storage Pool" \
    "3" "Delete VM" \
    "4" "VM Information" \
    "5" "Manage Network Interfaces" \
    "6" "Exit" 3>&1 1>&2 2>&3)

    case "$ACTION" in
        1) create_pool ;;
        2) delete_pool ;;
        3) delete_vm ;;
        4) vm_information ;;
        5) manage_network_interface ;;
        6) exit ;;
        *) echo "Invalid option." ;;
    esac
done
