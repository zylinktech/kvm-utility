#!/bin/bash

# Detect the user who invoked the script (even when running with sudo)
if [ "$SUDO_USER" ]; then
  user="$SUDO_USER"
else
  user="$USER"
fi

user_home=$(eval echo "~$user")
repo_dir="$(pwd)"  # Get the current working directory

# Use whiptail to prompt the user for the VM directory and storage pool name
vm_dir=$(whiptail --inputbox "Enter the directory where your VMs will be stored:" 10 60 "$user_home/VMs" --title "zylinktech kvm utility - setup" 3>&1 1>&2 2>&3)

pool_name=$(whiptail --inputbox "Enter the name of the storage pool:" 10 60 "default" --title "Storage Pool Setup" 3>&1 1>&2 2>&3 | tr -d '[:space:]')

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

# Check if the pool already exists, handle errors properly
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
if [ -f "$repo_dir/utility-wrapper.sh" ]; then
  echo "Copying utility-wrapper.sh to /usr/local/bin/..."
  sudo cp "$repo_dir/utility-wrapper.sh" /usr/local/bin/utility-wrapper.sh
  sudo chmod +x /usr/local/bin/utility-wrapper.sh
else
  echo "Warning: utility-wrapper.sh not found in $repo_dir."
fi

if [ -f "$repo_dir/os-types" ]; then
  echo "Copying os-types to /usr/local/bin/..."
  sudo cp "$repo_dir/os-types" /usr/local/bin/os-types
else
  echo "Warning: os-types not found in $repo_dir."
fi

# Copy the create_pool.sh script and set the alias
if [ -f "$repo_dir/create_pool.sh" ]; then
  echo "Copying create_pool.sh to /usr/local/bin/..."
  sudo cp "$repo_dir/create_pool.sh" /usr/local/bin/vm-createpool
  sudo chmod +x /usr/local/bin/vm-createpool
else
  echo "Warning: create_pool.sh not found in $repo_dir."
fi

# Create an alias for all users by adding it to /etc/bash.bashrc
if ! grep -q "alias vm-create=" /etc/bash.bashrc; then
  sudo sh -c "echo \"alias vm-create='bash /usr/local/bin/utility-wrapper.sh'\" >> /etc/bash.bashrc"
  echo "Alias 'vm-create' created."
else
  echo "Alias 'vm-create' already exists."
fi

# Create an alias for vm-createpool
if ! grep -q "alias vm-createpool=" /etc/bash.bashrc; then
  sudo sh -c "echo \"alias vm-createpool='bash /usr/local/bin/vm-createpool'\" >> /etc/bash.bashrc"
  echo "Alias 'vm-createpool' created."
else
  echo "Alias 'vm-createpool' already exists."
fi

# Reload the bashrc
source /etc/bash.bashrc

echo "Setup is complete. Run 'vm-create' to provision a VM, or 'vm-createpool' to create a new storage pool only."
