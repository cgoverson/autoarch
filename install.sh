#!/bin/bash

# Set up logging
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
exec 1> >(tee "stdout.log") 
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old

echo 'Server = https://plug-mirror.rcac.purdue.edu/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
echo 'Server = https://mirror.clarkson.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.rit.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirror.umd.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.mit.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.bloomu.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

pacman -Syy
pacman --noconfirm -S dialog

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac) 
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1 
clear

read -p 'Hostname for new installation: ' myhostname

# Calculate partition table
totalRam=$(grep MemTotal /proc/meminfo | sed 's/[^0-9]*//g')
totalRam=$(($totalRam+1000000))
totalDisk=$[ $(cat /sys/block/${device:5}/size) / 2 ]
offset=$(($totalDisk-$totalRam))

echo -e "g
n
1

+300M
t
1
n
2

+${totalRam}K
t
2
19
n
3


t
3
23
w" | fdisk $device

# TODO is there a need to ignore errors & force execution?
#mkfs.ext4 -F /dev/sda3
#mkfs.fat -I -F 32 /dev/sda1
#mkswap -f /dev/sda2

mkfs.fat -F 32 /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3

mount /dev/sda3 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
swapon /dev/sda2

pacstrap /mnt base base-devel

genfstab -U /mnt >> /mnt/etc/fstab

cp /etc/pacman.d/mirrorlist.old /mnt/etc/pacman.d/mirrorlist.old

echo -e "

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
echo -e 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
pacman -Syu intel-ucode networkmanager python nano sudo 
bootctl install


" | arch-chroot /mnt

echo ${myhostname} > /mnt/etc/hostname

echo -e "

" > /mnt/firstboot.sh
