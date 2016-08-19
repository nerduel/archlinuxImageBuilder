#!/bin/bash

echo -ne "\e[32mSetting up your hostname: ios.\e[0m" && read HOSTNAME
HOSTNAME="ios.${HOSTNAME}"
echo ${HOSTNAME} > /mnt/etc/hostname
echo -e "\e[32mconfiguring network device\e[0m"
cp /etc/dhcpcd.conf /mnt/etc/dhcpcd.conf
arch-chroot /mnt /usr/bin/systemctl enable dhcpcd.service
echo -e "\e[32mPlease set a root password\e[0m"
arch-chroot /mnt /usr/bin/passwd


arch-chroot /mnt /usr/bin/pacman vim gnome gnome-extra gdm intel-ucode tree
arch-chroot /mnt /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

echo -en "\e[32mPlease create a user, enter username: \e[0m" && read USERNAME
arch-chroot /mnt /usr/bin/useradd -m -G wheel -g users "${USERNAME}"
arch-chroot /mnt /usr/bin/passwd ${USERNAME}
umount -R /mnt
