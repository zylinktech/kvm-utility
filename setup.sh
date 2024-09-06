#!/bin/bash

# Ask user for the directory where VMs should be stored
read -p "Enter the directory where you want to store your VMs: " vm_directory

# Create the directory if it doesn't exist
if [ ! -d "$vm_directory" ]; then
    sudo mkdir -p "$vm_directory"
    sudo chmod 711 "$vm_directory"
    echo "Directory created at $vm_directory"
else
   ### Setup Script (continued):

```bash
    echo "Directory already exists at $vm_directory"
fi

# Define a new storage pool for VMs
virsh pool-define-as custompool dir --target "$vm_directory"

# Start and autostart the pool
virsh pool-start custompool
virsh pool-autostart custompool

# Verify the pool has been created
virsh pool-list --all

echo "VM storage pool set to $vm_directory"
