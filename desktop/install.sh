#!/bin/bash
# TODO:,fix password behavior, switch from systemdboot to clean efi,clean up ui choices, clean up existing xfce config files, set up clean firstboot / startxfce4 / xinit/bashprofile behavior?,check for standard errors?, delete temp.sh chrootscripts for user and root and clean up password file
# Moularization todo: |Primary install pacstrap script| > |Bootloader install chroot & then bootloader config non-chroot| > |UI & networking setup| > |User firstboot messages and scripts|

timedatectl set-ntp true

mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old

echo 'Server = https://plug-mirror.rcac.purdue.edu/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
echo 'Server = https://mirror.clarkson.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.rit.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirror.umd.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.mit.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
echo 'Server = https://mirrors.bloomu.edu/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

#pacman-key --init
#pacman-key --populate archlinux
pacman -Sy
#pacman --noconfirm -S archlinux-keyring
pacman --noconfirm -S dialog

lsblk -dplnx size -o name,size

# Old way of getting info:
#read -p 'Device for new installation: ' device
# New way of getting info:
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1

useTrim=$(hdparm -I /dev/${device} | grep TRIM)

myhostname=$(dialog --stdout --inputbox "Enter name for this computer" 0 0) || exit 1
: ${myhostname:?"hostname cannot be empty"}
myusername=$(dialog --stdout --inputbox "Enter username" 0 0) || exit 1
: ${myusername:?"username cannot be empty"}

mypassword=ab
mypassword2=cd
while [ "$mypassword" != "$mypassword2" ]
do
  echo -n "Password for ${myusername}: "
  read -s mypassword
  echo
  echo -n "Repeat Password: "
  read -s mypassword2
  echo
  [[ "$mypassword" == "$mypassword2" ]] || ( echo "Passwords did not match. Please retype"; )
done

# Detect efi mode
if [ -d "/sys/firmware/efi/efivars" ]; then
  efiDetect=1
else
  efiDetect=0
fi

# Calculate partition table
totalRam=$(grep MemTotal /proc/meminfo | sed 's/[^0-9]*//g')
totalRam=$(($totalRam+1000000))

# Use fdisk manually so that it dynamically recognizes how much can be used for root dir after /boot and swap
if ["$efiDetect" = 1]; then
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

# For some reason mkfs doesn't like using variable names for devices, so temp.sh is created
  echo "mkfs.fat -F 16 ${device}1" > temp.sh
  echo "mkswap ${device}2" >> temp.sh
  echo "mkfs.ext4 ${device}3" >> temp.sh
  echo "mount ${device}3 /mnt" >> temp.sh
  echo "mkdir /mnt/boot" >> temp.sh
  echo "mount ${device}1 /mnt/boot" >> temp.sh
  echo "swapon ${device}2" >> temp.sh
  chmod 777 temp.sh
  ./temp.sh
  #rm temp.sh
else
  echo -e "o
n
p
1

+${totalRam}K
t
82
n
p
2

-20K
t
2
83
a
2
w" | fdisk $device

# For some reason mkfs doesn't like using variable names for devices, so temp.sh is created
  echo "mkswap ${device}1" >> temp.sh
  echo "mkfs.ext4 ${device}2" >> temp.sh
  echo "mount ${device}2 /mnt" >> temp.sh
  echo "swapon ${device}1" >> temp.sh
  chmod 777 temp.sh
  ./temp.sh
  #rm temp.sh
fi

pacstrap /mnt base linux linux-firmware base-devel

genfstab -U /mnt >> /mnt/etc/fstab

# Set up temporary file for setting password later
echo -e "${mypassword}\n${mypassword}" > /mnt/root/temp

# Create a chroot script and call it manually due to quotation & variable call limitations in bash
echo -e "
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
echo -e 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
sed -i 's/udev/udev resume/g' /etc/mkinitcpio.conf
pacman -Syu --noconfirm intel-ucode networkmanager python nano
" > /mnt/root/chrootscr.sh

if ["$efiDetect" = 1]; then
  echo -e "
bootctl install
echo 'default arch.conf' > /boot/loader/loader.conf
echo 'editor  no' >> /boot/loader/loader.conf
rm -rf /boot/loader/entries/*
echo 'title Arch Linux' > /boot/loader/entries/arch.conf
echo 'linux /vmlinuz-linux' >> /boot/loader/entries/arch.conf
echo 'initrd /intel-ucode.img' >> /boot/loader/entries/arch.conf
echo 'initrd /initramfs-linux.img' >> /boot/loader/entries/arch.conf
echo 'title Arch Linux Fallback' > /boot/loader/entries/arch-fallback.conf
echo 'linux /vmlinuz-linux' >> /boot/loader/entries/arch-fallback.conf
echo 'initrd /intel-ucode.img' >> /boot/loader/entries/arch-fallback.conf
echo 'initrd /initramfs-linux-fallback.img' >> /boot/loader/entries/arch-fallback.conf
echo '[Trigger]' > /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'Type = Package' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'Operation = Upgrade' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'Target = systemd' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo '' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo '[Action]' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'Description = Gracefully upgrading systemd-boot...' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'When = PostTransaction' >> /etc/pacman.d/hooks/95-systemd-boot.hook
echo 'Exec = /usr/bin/bootctl update' >> /etc/pacman.d/hooks/95-systemd-boot.hook
" >> /mnt/root/chrootscr.sh
else
  echo -e "
pacman -Syu --noconfirm syslinux
syslinux-install_update -i -a -m
sed -i 's/TIMEOUT 50/TIMEOUT 15/g' /boot/syslinux/syslinux.cfg
sed -i 's|INITRD ../initramfs-linux.img|INITRD ../intel-ucode.img,../initramfs-linux.img|g' /boot/syslinux/syslinux.cfg
sed -i 's|INITRD ../initramfs-linux-fallback.img|INITRD ../intel-ucode.img,../initramfs-linux-fallback.img|g' /boot/syslinux/syslinux.cfg
" >> /mnt/root/chrootscr.sh
fi

echo -e "
echo ${myhostname} > /etc/hostname
useradd -m -g wheel -G audio ${myusername}
cat /root/temp | passwd ${myusername}
passwd --lock root
pacman -Syu --noconfirm gvfs xorg-server pipewire-jack pipewire-alsa pipewire-pulse wireplumber pipewire xf86-video-intel mesa xfce4 xfce4-whiskermenu-plugin ttf-dejavu chromium network-manager-applet xfce4-pulseaudio-plugin xfce4-screensaver xfce4-session
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
systemctl enable NetworkManager.service
" >> /mnt/root/chrootscr.sh

if [[ $useTrim == *"TRIM supported"* ]]; then
  echo -e "
systemctl enable fstrim.timer
" >> /mnt/root/chrootscr.sh
fi

# Run chroot script
echo -e "
chmod 777 /root/chrootscr.sh
./root/chrootscr.sh
#rm /root/chrootscr.sh
#cat /dev/null > /root/temp
" | arch-chroot /mnt

if ["$efiDetect" = 1]; then
  mypartuuid=$(blkid -s PARTUUID -o value ${device}3)
  echo "options root=PARTUUID=${mypartuuid} rw resume=${device}2" >> /mnt/boot/loader/entries/arch.conf
  echo "options root=PARTUUID=${mypartuuid} rw" >> /mnt/boot/loader/entries/arch-fallback.conf
else
  sed -i "s|APPEND root=/dev/sda3 rw|APPEND root=${device}2 rw resume=${device}1|g" /mnt/boot/syslinux/syslinux.cfg
fi


# Clean up temporary password file
#cat /dev/null > /mnt/root/temp
#rm /mnt/root/temp

# Create user chroot script
echo -e "
mkdir ~/.config
mkdir ~/.config/xfce4
mkdir ~/.config/xfce4/panel
mkdir ~/.config/xfce4/xfconf
mkdir ~/.config/xfce4/xfconf/xfce-perchannel-xml

chmod 755 ~/.config
chmod 755 ~/.config/xfce4
chmod 755 ~/.config/xfce4/panel
chmod 755 ~/.config/xfce4/xfconf
chmod 755 ~/.config/xfce4/xfconf/xfce-perchannel-xml

echo 'WebBrowser=chromium' >> /home/${myusername}/.config/xfce4/helpers.rc
curl https://raw.githubusercontent.com/cgoverson/autoarch/main/desktop/whiskermenu-7.rc >> ~/.config/xfce4/panel/whiskermenu-7.rc
curl https://raw.githubusercontent.com/cgoverson/autoarch/main/desktop/xfce4-keyboard-shortcuts.xml >> ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
curl https://raw.githubusercontent.com/cgoverson/autoarch/main/desktop/xfce4-panel.xml >> ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

chmod 644 ~/.config/xfce4/helpers.rc
chmod 644 ~/.config/xfce4/panel/whiskermenu-7.rc
chmod 644 ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
chmod 644 ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

" > /mnt/home/${myusername}/chrootscr.sh

# Run user chroot script
echo -e "
chmod 777 /home/${myusername}/chrootscr.sh
cd /home/${myusername}
su ${myusername}
./chrootscr.sh
#rm chrootscr.sh
exit
" | arch-chroot /mnt

# Create firstboot script
echo -e "
xfconf-query -c xfce4-session -p /general/SaveOnExit -s false
" > /mnt/home/${myusername}/firstbootuser.sh

exit
