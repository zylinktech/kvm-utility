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

# Enable and start the libvirtd service
sudo systemctl enable --now libvirtd
sudo systemctl start libvirtd

echo "Setup is complete. Your VMs will be stored in $vm_dir"
