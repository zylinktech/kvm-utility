#!/bin/bash

# Prompt for pool name and directory path
pool_name=$(whiptail --inputbox "Enter the name of the new storage pool:" 10 60 "newpool" --title "Create Storage Pool" 3>&1 1>&2 2>&3)
pool_dir=$(whiptail --inputbox "Enter the directory path for the storage pool:" 10 60 "/var/lib/libvirt/images" --title "Create Storage Pool" 3>&1 1>&2 2>&3)

# Check if the directory exists, create it if not
if [ ! -d "$pool_dir" ]; then
  sudo mkdir -p "$pool_dir"
  echo "Directory $pool_dir created."
else
  echo "Directory $pool_dir already exists."
fi

# Define and start the storage pool
sudo virsh pool-define-as --name "$pool_name" --type dir --target "$pool_dir"
sudo virsh pool-start "$pool_name"
sudo virsh pool-autostart "$pool_name"

echo "Storage pool '$pool_name' created and started at '$pool_dir'."
