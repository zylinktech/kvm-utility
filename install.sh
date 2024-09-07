#!/bin/bash
sudo apt update
sudo apt upgrade -y

sudo apt install -y qemu-kvm
sudo apt install -y libvirt-daemon-system
sudo apt install -y libvirt-clients
sudo apt install -y bridge-utils
sudo apt install -y virt-manager
sudo apt install -y cpu-checker

sudo apt install -y whiptail
clear
sudo kvm-ok
echo ""
echo "System restart recommended."
