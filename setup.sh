#!/bin/bash

# Detect the user who invoked the script (even when running with sudo)
if [ "$SUDO_USER" ]; then
  actual_user="$SUDO_USER"
else
  actual_user="$USER"
fi

user_home=$(eval echo "~$actual_user")

# Use whiptail to prompt the user for the VM directory and storage pool name
vm_dir=$(whiptail --inputbox "Enter the directory where your VMs will be stored:" 10 60 "$user_home/vm" --title "VM Setup" 3>&1 1>&2 2>&3)

pool_name=$(whiptail --inputbox "Enter the name of the storage pool:" 10 60 "default" --title "Storage Pool Setup" 3>&1 1>&2 2>&3)

# Check if the directory exists, create it if not
if [ ! -d "$vm_dir" ]; then
  mkdir -p "$vm_dir"
  echo "Directory $vm_dir created."
else
  echo "Directory $vm_dir already exists."
fi

# Display available system memory and directory storage usage
available_memory=$(free -h | awk '/Mem:/ {print $2}')
dir_usage=$(du -sh "$vm_dir" 2>/dev/null | awk '{print $1}')
dir_total=$(df -h "$vm_dir" | awk 'NR==2 {print $2}')
dir_used=$(df -h "$vm_dir" | awk 'NR==2 {print $3}')

echo "Available RAM: $available_memory"
echo "$dir_used of $dir_total used."

# Enable and start the libvirtd service
sudo systemctl enable --now libvirtd
sudo systemctl start libvirtd

# Check if the pool already exists
if sudo virsh pool-info "$pool_name" &> /dev/null; then
  echo "Pool '$pool_name' already exists."
else
  # Create and configure the storage pool if it doesn't exist
  sudo virsh pool-define-as --name "$pool_name" --type dir --target "$vm_dir"
  sudo virsh pool-start "$pool_name"
  sudo virsh pool-autostart "$pool_name"
  echo "Storage pool '$pool_name' created and started."
fi

# Move utility-wrapper.sh and os-types from the GitHub repo to /usr/local/bin/
repo_dir="$user_home/kvm-utility"
if [ -f "$repo_dir/utility-wrapper.sh" ]; then
  sudo mv "$repo_dir/utility-wrapper.sh" /usr/local/bin/utility-wrapper.sh
  sudo chmod +x /usr/local/bin/utility-wrapper.sh
else
  echo "Warning: utility-wrapper.sh not found in $repo_dir."
fi

if [ -f "$repo_dir/os-types" ]; then
  sudo mv "$repo_dir/os-types" /usr/local/bin/os-types
else
  echo "Warning: os-types not found in $repo_dir."
fi

# Create an alias for all users by adding it to /etc/bash.bashrc
sudo sh -c "echo \"alias vm-create='bash /usr/local/bin/utility-wrapper.sh'\" >> /etc/bash.bashrc"

echo "Setup is complete. Run 'vm-create' to provision a VM."
