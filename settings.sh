#!/bin/bash

LOG_FILE="/var/log/kvm-utility.log"

# Function to log messages
log() {
    echo "$(date) - $1" >> "$LOG_FILE"
}

# Function to convert a netmask to CIDR notation
netmask_to_cidr() {
    local netmask=$1
    local x
    local cidr=0

    IFS=. read -r i1 i2 i3 i4 <<< "$netmask"
    for x in $i1 $i2 $i3 $i4; do
        case $x in
            255) let cidr+=8 ;;
            254) let cidr+=7 ;;
            252) let cidr+=6 ;;
            248) let cidr+=5 ;;
            240) let cidr+=4 ;;
            224) let cidr+=3 ;;
            192) let cidr+=2 ;;
            128) let cidr+=1 ;;
            0) ;;
            *) return 1 ;;  # Invalid netmask
        esac
    done
    echo "$cidr"
}

# Function to create a storage pool
create_pool() {
    pool_name=$(whiptail --inputbox "Enter the storage pool name:" 10 60 "newpool" --title "Create Storage Pool" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$pool_name" ]; then
        return
    fi
    
    pool_dir=$(whiptail --inputbox "Enter the directory for the storage pool:" 10 60 "/var/lib/libvirt/images" --title "Storage Pool Directory" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$pool_dir" ]; then
        return
    fi

    # Create and start the storage pool
    sudo virsh pool-define-as --name "$pool_name" --type dir --target "$pool_dir"
    if [ $? -eq 0 ]; then
        sudo virsh pool-start "$pool_name"
        sudo virsh pool-autostart "$pool_name"
        log "Storage pool '$pool_name' created at '$pool_dir'."
        whiptail --title "Success" --msgbox "Storage pool '$pool_name' created and started at '$pool_dir'." 10 60
    else
        whiptail --title "Error" --msgbox "Failed to create storage pool '$pool_name'." 10 60
        log "Failed to create storage pool '$pool_name'."
    fi
}

# Function to delete a storage pool
delete_pool() {
    available_pools=$(sudo virsh pool-list --all | awk 'NR>2 {print $1}')

    if [ -z "$available_pools" ]; then
        whiptail --title "Error" --msgbox "No storage pools available to delete." 10 60
        return
    fi

    pool_options=()
    for pool in $available_pools; do
        pool_options+=("$pool" "$pool")
    done

    selected_pool=$(whiptail --title "Delete Storage Pool" --menu "Select a storage pool to delete:" 15 60 5 "${pool_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_pool" ]; then
        return
    fi

    sudo virsh pool-destroy "$selected_pool"
    sudo virsh pool-undefine "$selected_pool"
    whiptail --title "Success" --msgbox "Storage pool '$selected_pool' deleted successfully." 10 60
    log "Storage pool '$selected_pool' deleted."
}

# Function to list storage pools
list_storage_pools() {
    pool_info=$(sudo virsh pool-list --all)
    if [ -z "$pool_info" ]; then
        whiptail --title "Error" --msgbox "No storage pools found." 10 60
        return
    fi
    whiptail --title "Storage Pools" --msgbox "$pool_info" 15 60
}

# Function to create a network bridge
create_bridge() {
    bridge_name=$(whiptail --inputbox "Enter the bridge name (e.g., br0):" 10 60 "br0" --title "Create Network Bridge" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$bridge_name" ]; then
        return
    fi

    interfaces=$(ip link show | grep -E '^[0-9]+: ' | awk -F: '{print $2}' | xargs)
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No network interfaces found." 10 60
        return
    fi

    interface_options=()
    for iface in $interfaces; do
        interface_options+=("$iface" "$iface")
    done

    selected_interface=$(whiptail --title "Select Interface" --menu "Select a physical interface to attach to the bridge:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_interface" ]; then
        return
    fi

    sudo nmcli connection add type bridge con-name "$bridge_name" ifname "$bridge_name"
    sudo nmcli connection add type bridge-slave ifname "$selected_interface" master "$bridge_name"
    sudo nmcli connection up "$bridge_name"
    whiptail --title "Success" --msgbox "Bridge $bridge_name created and connected to interface $selected_interface." 10 60
    log "Bridge $bridge_name created with physical interface $selected_interface."
}

# Function to create a virtual network (vnet)
create_vnet() {
    vnet_name=$(whiptail --inputbox "Enter the virtual network (vnet) name:" 10 60 "vnet0" --title "Create Virtual Network" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$vnet_name" ]; then
        return
    fi

    IP_ADDRESS=$(whiptail --inputbox "Enter the IP address for the virtual network (e.g., 192.168.100.1):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$IP_ADDRESS" ]; then
        return
    fi

    NETMASK=$(whiptail --inputbox "Enter the subnet mask (e.g., 255.255.255.0):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$NETMASK" ]; then
        return
    fi

    CIDR=$(netmask_to_cidr "$NETMASK")

    # Create XML configuration for the virtual network
    cat <<EOF > /tmp/$vnet_name.xml
<network>
  <name>$vnet_name</name>
  <bridge name='$vnet_name' stp='on' delay='0'/>
  <forward mode='nat'/>
  <ip address='$IP_ADDRESS' netmask='$NETMASK'>
    <dhcp>
      <range start='${IP_ADDRESS%.*}.50' end='${IP_ADDRESS%.*}.200'/>
    </dhcp>
  </ip>
</network>
EOF

    sudo virsh net-define /tmp/$vnet_name.xml
    sudo virsh net-start $vnet_name
    sudo virsh net-autostart $vnet_name
    rm /tmp/$vnet_name.xml
    whiptail --title "Success" --msgbox "Virtual network $vnet_name created and started with IP $IP_ADDRESS and Netmask $NETMASK." 10 60
    log "Virtual network $vnet_name created and started with IP $IP_ADDRESS and Netmask $NETMASK."
}

# Function to edit virbr0 network (Auto or Manual)
edit_virbr0_network() {
    CONFIG_TYPE=$(whiptail --title "Edit virbr0" --menu "Choose configuration type:" 15 60 2 \
    "1" "Auto (DHCP)" \
    "2" "Manual (Static)" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return
    fi

    if [ "$CONFIG_TYPE" == "1" ]; then
        sudo nmcli connection modify virbr0 ipv4.method auto
        sudo nmcli connection up virbr0
        whiptail --title "Success" --msgbox "virbr0 is now configured to use DHCP (Auto)." 10 60
        log "virbr0 set to auto (DHCP)."
    elif [ "$CONFIG_TYPE" == "2" ]; then
        GATEWAY=$(whiptail --inputbox "Enter the gateway address:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return
        fi

        SUBNET=$(whiptail --inputbox "Enter the subnet mask (e.g., 255.255.255.0):" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return
        fi

        DEVICE_IP=$(whiptail --inputbox "Enter the device IP address (optional):" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return
        fi

        DNS=$(whiptail --inputbox "Enter the DNS server (optional):" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return
        fi

        CIDR=$(netmask_to_cidr "$SUBNET")

        sudo nmcli connection modify virbr0 ipv4.method manual ipv4.addresses "$DEVICE_IP/$CIDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS"
        sudo nmcli connection up virbr0
        whiptail --title "Success" --msgbox "virbr0 is now manually configured." 10 60
        log "virbr0 set to manual: IP=$DEVICE_IP, Gateway=$GATEWAY, Subnet=$CIDR, DNS=$DNS"
    fi
}

# Function to delete a network interface
delete_network_interface() {
    interfaces=$(ip link show | grep -E '^[0-9]+: ' | awk -F: '{print $2}' | xargs)
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No network interfaces found to delete." 10 60
        return
    fi

    interface_options=()
    for iface in $interfaces; do
        interface_options+=("$iface" "$iface")
    done

    selected_interface=$(whiptail --title "Delete Network Interface" --menu "Select an interface to delete:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_interface" ]; then
        return
    fi

    sudo nmcli connection delete "$selected_interface"
    whiptail --title "Success" --msgbox "Network interface $selected_interface deleted." 10 60
    log "Network interface $selected_interface deleted."
}

# Function to attach a network interface to a VM
attach_network_interface() {
    selected_vm="$1"

    available_bridges=$(sudo virsh net-list --all | awk 'NR>2 {print $1}')
    if [ -z "$available_bridges" ]; then
        whiptail --title "Error" --msgbox "No available bridges." 10 60
        return
    fi

    bridge_options=()
    for bridge in $available_bridges; do
        bridge_options+=("$bridge" "$bridge")
    done

    selected_bridge=$(whiptail --title "Attach Network Interface" --menu "Select a bridge to attach:" 15 60 5 "${bridge_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_bridge" ]; then
        return
    fi

    sudo virsh attach-interface --domain "$selected_vm" --type bridge --source "$selected_bridge" --model virtio --config --live
    whiptail --title "Success" --msgbox "Interface attached to VM $selected_vm using bridge $selected_bridge." 10 60
    log "Interface attached to VM $selected_vm using bridge $selected_bridge."
}

# Function to detach a network interface from a VM
detach_network_interface() {
    selected_vm="$1"

    interfaces=$(sudo virsh domiflist "$selected_vm" | awk 'NR>2 {print $1}')
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No interfaces found for VM $selected_vm." 10 60
        return
    fi

    interface_options=()
    for iface in $interfaces; do
        interface_options+=("$iface" "$iface")
    done

    selected_iface=$(whiptail --title "Detach Network Interface" --menu "Select an interface to detach from VM $selected_vm:" 15 60 5 "${interface_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_iface" ]; then
        return
    fi

    sudo virsh detach-interface "$selected_vm" bridge --mac "$selected_iface" --config --live
    whiptail --title "Success" --msgbox "Interface detached from VM $selected_vm." 10 60
    log "Interface detached from VM $selected_vm."
}

# Function to change VM storage pool
change_vm_pool() {
    vm_name="$1"
    available_pools=$(sudo virsh pool-list --all | awk 'NR>2 {print $1}')

    if [ -z "$available_pools" ]; then
        whiptail --title "Error" --msgbox "No storage pools available." 10 60
        return
    fi

    pool_options=()
    for pool in $available_pools; do
        pool_options+=("$pool" "$pool")
    done

    selected_pool=$(whiptail --title "Change Storage Pool" --menu "Select a storage pool to move VM $vm_name to:" 15 60 5 "${pool_options[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$selected_pool" ]; then
        return
    fi

    vm_disk=$(sudo virsh domblklist "$vm_name" | grep vda | awk '{print $2}')
    new_disk_path="/var/lib/libvirt/images/$selected_pool/$vm_name.qcow2"

    sudo virsh dumpxml "$vm_name" > /tmp/$vm_name.xml
    sudo virsh destroy "$vm_name"
    sudo mv "$vm_disk" "$new_disk_path"
    sudo sed -i "s|$vm_disk|$new_disk_path|" /tmp/$vm_name.xml
    sudo virsh define /tmp/$vm_name.xml
    sudo virsh start "$vm_name"
    rm /tmp/$vm_name.xml

    whiptail --title "Success" --msgbox "VM $vm_name moved to storage pool $selected_pool." 10 60
    log "VM $vm_name moved to storage pool $selected_pool."
}

# Function to manage VMs (start, stop, restart, delete, change pool, attach/detach interfaces)
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

    selected_vm=$(whiptail --title "Manage VM" --menu "Select a VM to manage:" 15 60 5 "${vm_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return
    fi

    vm_action=$(whiptail --title "Manage VM" --menu "Choose an action for VM $selected_vm:" 15 60 8 \
    "1" "Start VM" \
    "2" "Stop VM" \
    "3" "Restart VM" \
    "4" "Delete VM" \
    "5" "Change Storage Pool" \
    "6" "Attach Network Interface" \
    "7" "Detach Network Interface" 3>&1 1>&2 2>&3)

    case "$vm_action" in
        1) sudo virsh start "$selected_vm"; whiptail --title "Success" --msgbox "VM $selected_vm started." 10 60; log "VM $selected_vm started." ;;
        2) sudo virsh shutdown "$selected_vm"; whiptail --title "Success" --msgbox "VM $selected_vm stopped." 10 60; log "VM $selected_vm stopped." ;;
        3) sudo virsh reboot "$selected_vm"; whiptail --title "Success" --msgbox "VM $selected_vm restarted." 10 60; log "VM $selected_vm restarted." ;;
        4) 
            sudo virsh destroy "$selected_vm"
            sudo virsh undefine "$selected_vm"
            whiptail --title "Success" --msgbox "VM $selected_vm deleted." 10 60
            log "VM $selected_vm deleted."
        ;;
        5) change_vm_pool "$selected_vm" ;;
        6) attach_network_interface "$selected_vm" ;;
        7) detach_network_interface "$selected_vm" ;;
    esac
}

# Main menu loop
while true; do
    ACTION=$(whiptail --title "KVM Utility Settings" --menu "Choose an action:" 15 60 6 \
    "1" "Storage Management" \
    "2" "Manage Network Interfaces" \
    "3" "VM Management" \
    "4" "Exit" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        break
    fi

    case "$ACTION" in
        1) 
            STORAGE_ACTION=$(whiptail --title "Storage Management" --menu "Choose an action:" 15 60 4 \
            "1" "Create Storage Pool" \
            "2" "Delete Storage Pool" \
            "3" "List Storage Pools" \
            "4" "Back" 3>&1 1>&2 2>&3)
            case "$STORAGE_ACTION" in
                1) create_pool ;;
                2) delete_pool ;;
                3) list_storage_pools ;;
            esac
        ;;
        2) 
            NETWORK_ACTION=$(whiptail --title "Manage Network Interfaces" --menu "Choose an action:" 15 60 4 \
            "1" "Create Network Bridge" \
            "2" "Create Virtual Network (vnet)" \
            "3" "Edit virbr0" \
            "4" "Delete Network Interface" 3>&1 1>&2 2>&3)
            case "$NETWORK_ACTION" in
                1) create_bridge ;;
                2) create_vnet ;;
                3) edit_virbr0_network ;;
                4) delete_network_interface ;;
            esac
        ;;
        3) manage_vm ;;
        4) exit ;;
    esac
done
