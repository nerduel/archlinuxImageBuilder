#!/bin/bash

echo
echo -e "\e[32mstarting locale-gen\e[0m"
sed -i -e "s,^\#de_DE.UTF8,de_DE.UTF8,g" -e "s,^\#en_US.UTF8,en_US.UTF8,g" /mnt/etc/locale.gen
arch-chroot /mnt /bin/locale-gen
echo -e "\e[32msetting locale conf and vconsole conf\e[0m"
echo -e "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo -e "KEYMAP=de-latin1\nFONT=lat9w-16" > /mnt/etc/vconsole.conf
echo -e "\e[32mset up time\e[0m"
arch-chroot /mnt /bin/tzselect
arch-chroot /mnt /bin/ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
arch-chroot /mnt /bin/hwclock --systohc --utc
${EDITOR}  /mnt/etc/mkinitcpio.conf
echo -e "\e[32mgenerate initramfs\e[0m"
arch-chroot /mnt /usr/bin/mkinitcpio -p linux
echo -e "\e[32minstalling grub\e[0m"

arch-chroot /mnt /usr/bin/pacman -S os-prober

YESNO="$(echo -e "Yes\nNo")"
selector "${YESNO}" "Do you use UEFI?" "no_skip"
if [[ $(select_input "${YESNO}" ${SELECT}) == "Yes" ]];
then
	arch-chroot /mnt /usr/bin/mount -t efivarfs efivarfs /sys/firmware/efi/efivars
	arch-chroot /mnt /usr/bin/pacman -S grub efibootmgr dosfstools
	arch-chroot /mnt /usr/bin/grub-install --target=x86_64-efi \
		--efi-directory=/boot \
		--bootloader-id=arch_grub \
		--recheck \
		--debug

	YESNO="$(echo -e "Yes\nNo")"
	selector "${YESNO}" "ANY ERRORS WHILE GRUB-INSTALL (efibootmgr)?" "no_skip"
	if [[ $(select_input "${YESNO}" ${SELECT}) == "No" ]];
	then
		arch-chroot /mnt /usr/bin/mkdir -p /boot/grub/locale
		arch-chroot /mnt /usr/bin/cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo \
					     /boot/grub/locale/en.mo 
		arch-chroot /mnt /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
	else
		echo
		echo "YOU SHOULD INSTALL GRUB BY YOURSELF, SORRY!!"		
		exit 1
	fi
else
	arch-chroot /mnt /usr/bin/pacman -S grub
	arch-chroot /mnt /usr/bin/grub-install --recheck /dev/sda
	arch-chroot /mnt /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
fi

source ./finish.sh
