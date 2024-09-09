#!/bin/bash

# Function to log messages
log() {
    echo "$(date) - $1" >> "/var/log/kvm-utility.log"
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
    # Get the invoking user's home directory
    user_home=$(get_home_directory)
    
    # Provide the default pool directory as ~/VMs
    pool_dir=$(whiptail --inputbox "Enter the directory for the storage pool:" 10 60 "$user_home/VMs" --title "Create Storage Pool" 3>&1 1>&2 2>&3)

    # Check if the user canceled the input
    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    # Validate the directory path
    if [ -z "$pool_dir" ]; then
        whiptail --title "Error" --msgbox "Invalid directory path. Please try again." 8 60
        log "Invalid directory path entered."
        return
    fi

    # Create the directory if it doesn't exist
    if [ ! -d "$pool_dir" ]; then
        mkdir -p "$pool_dir"
        echo "Directory $pool_dir created."
        log "Directory $pool_dir created."
    else
        echo "Directory $pool_dir already exists."
        log "Directory $pool_dir already exists."
    fi

    # Ask for the storage pool name
    pool_name=$(whiptail --inputbox "Enter the name of the new storage pool:" 10 60 "newpool" --title "Create Storage Pool" 3>&1 1>&2 2>&3)

    # Check if the user canceled the input
    if [ $? -ne 0 ]; then
        echo "Operation canceled."
        return
    fi

    # Validate the pool name
    if [ -z "$pool_name" ]; then
        whiptail --title "Error" --msgbox "Invalid pool name. Please try again." 8 60
        log "Invalid pool name entered."
        return
    fi

    # Define and start the storage pool
    sudo virsh pool-define-as --name "$pool_name" --type dir --target "$pool_dir"
    if [ $? -eq 0 ]; then
        sudo virsh pool-start "$pool_name"
        sudo virsh pool-autostart "$pool_name"
        echo "Storage pool '$pool_name' created and started at '$pool_dir'."
        log "Storage pool '$pool_name' created at '$pool_dir'."
        
        # Get the pool info and display the disk size
        pool_info=$(sudo virsh pool-info "$pool_name")
        total_size=$(echo "$pool_info" | grep 'Capacity' | awk '{print $2, $3}')
        free_size=$(echo "$pool_info" | grep 'Available' | awk '{print $2, $3}')
        whiptail --title "Pool Info" --msgbox "Storage pool '$pool_name' created at '$pool_dir'.\nTotal Size: $total_size\nFree Space: $free_size" 10 60
        log "Storage pool '$pool_name' info: Total Size: $total_size, Free Space: $free_size"
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
        echo "VM '$selected_vm' deleted."
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
        # Get the pool information
        pool_info=$(sudo virsh pool-info "$pool")
        total_size=$(echo "$pool_info" | grep 'Capacity' | awk '{print $2, $3}')
        free_size=$(echo "$pool_info" | grep 'Available' | awk '{print $2, $3}')
        
        # Calculate used size
        used_size=$(echo "$total_size - $free_size" | bc)
        
        # Add the pool name with size information to the menu options
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
        echo "Storage pool '$selected_pool' deleted."
        log "Storage pool '$selected_pool' deleted."
    else
        echo "Storage pool '$selected_pool' not found."
        log "Storage pool '$selected_pool' not found."
    fi
}

# Main menu loop
while true; do
    ACTION=$(whiptail --title "KVM Utility Settings" --menu "Choose an action:" 15 60 4 \
    "1" "Create Storage Pool" \
    "2" "Delete Storage Pool" \
    "3" "Delete VM" \
    "4" "Exit" 3>&1 1>&2 2>&3)

    case "$ACTION" in
        1) create_pool ;;
        2) delete_pool ;;
        3) delete_vm ;;
        4) exit ;;
        *) echo "Invalid option." ;;
    esac
done
