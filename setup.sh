#!/bin/bash

# Prompt the user to enter the directory for storing VMs
read -p "Setup - Enter VM directory. This is where your VMs will be stored: " vm_dir

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

# Move utility-wrapper.sh and os-types to /usr/local/bin/
sudo mv utility-wrapper.sh /usr/local/bin/utility-wrapper.sh
sudo mv os-types /usr/local/bin/os-types

# Give executable permissions to utility-wrapper.sh
sudo chmod +x /usr/local/bin/utility-wrapper.sh

# Create an alias for all users by adding it to /etc/bash.bashrc
sudo sh -c "echo \"alias vm-create='bash /usr/local/bin/utility-wrapper.sh'\" >> /etc/bash.bashrc"

echo "Setup is complete. Run 'vm-create' to provision a VM."
