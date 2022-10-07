#!/bin/bash

boot=($(lsblk --list --fs | grep FAT32))
boot_drive=/dev/${boot[0]}

sudo umount $boot_drive
sudo mkfs.fat -F32 $boot_drive
sudo systemctl daemon-reload
sudo mount $boot_drive /boot/efi
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=KOOMPI_OS
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo bash -c 'genfstab -U -p / > /etc/fstab'