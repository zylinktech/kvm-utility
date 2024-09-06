#!/bin/bash

sudo apt upgrade -y qemu-kvm
sudo apt upgrade -y libvirt-daemon-system
sudo apt upgrade -y libvirt-clients
sudo apt upgrade -y bridge-utils
sudo apt upgrade -y virt-manager
sudo apt upgrade -y cpu-checker
sudo apt upgrade -y whiptail
cd ~
sudo rm -rf ./kvm-utility && sudo git clone https://github.com/zylinktech/kvm-utility/new/main
cd ./kvm-utility
sudo kvm-ok
