# zfsbootmenu
## Configure Live Environment
#### Open a root shell
Open a terminal on the live installer session, then:
```bash
sudo -i
```

Confirm EFI support:
```bash
dmesg | grep -i efivars
```


#### Source `/etc/os-release`
The file /etc/os-release defines variables that describe the running distribution. In particular, the $ID variable defined within can be used as a short name for the filesystem that will hold this installation.
```bash
source /etc/os-release
export ID
```

#### Install helpers
```bash
apt update
apt install debootstrap gdisk zfsutils-linux
```

#### Generate `/etc/hostid`
```bash
zgenhostid -f 0x00bab10c
```


## Define disk variables
Takes two NVMe drives in mirror
```bash
export BOOT_DISK1="/dev/nvme0n1"
export BOOT_PART1="1"
export BOOT_DEVICE1="${BOOT_DISK1}p${BOOT_PART1}"
export POOL_DISK1="/dev/nvme0n1"
export POOL_PART1="2"
export POOL_DEVICE1="${POOL_DISK1}p${POOL_PART1}"
export BOOT_DISK2="/dev/nvme1n1"
export BOOT_PART2="1"
export BOOT_DEVICE2="${BOOT_DISK2}p${BOOT_PART2}"
export POOL_DISK2="/dev/nvme1n1"
export POOL_PART2="2"
export POOL_DEVICE2="${POOL_DISK2}p${POOL_PART2}"
```
Takes 2 SATA drives in mirror
```bash
export BOOT_DISK1="/dev/sda"
export BOOT_PART1="1"
export BOOT_DEVICE1="${BOOT_DISK1}${BOOT_PART1}"
export POOL_DISK1="/dev/sda"
export POOL_PART1="2"
export POOL_DEVICE1="${POOL_DISK1}${POOL_PART1}"
export BOOT_DISK2="/dev/sdb"
export BOOT_PART2="1"
export BOOT_DEVICE2="${BOOT_DISK2}${BOOT_PART2}"
export POOL_DISK2="/dev/sdb"
export POOL_PART2="2"
export POOL_DEVICE2="${POOL_DISK2}${POOL_PART2}"
```

## Disk preparation
#### Wipe partitions
```bash
zpool labelclear -f "$POOL_DISK1"

wipefs -a "$POOL_DISK1"
wipefs -a "$BOOT_DISK1"

sgdisk --zap-all "$POOL_DISK1"
sgdisk --zap-all "$BOOT_DISK1"

zpool labelclear -f "$POOL_DISK2"

wipefs -a "$POOL_DISK2"
wipefs -a "$BOOT_DISK2"

sgdisk --zap-all "$POOL_DISK2"
sgdisk --zap-all "$BOOT_DISK2"
```

#### Create EFI boot and zpool partition
```bash
sgdisk -n "${BOOT_PART1}:1m:+512m" -t "${BOOT_PART1}:ef00" "$BOOT_DISK1"
sgdisk -n "${BOOT_PART2}:1m:+512m" -t "${BOOT_PART2}:ef00" "$BOOT_DISK2"
sgdisk -n "${POOL_PART1}:0:-10m" -t "${POOL_PART1}:bf00" "$POOL_DISK1"
sgdisk -n "${POOL_PART2}:0:-10m" -t "${POOL_PART2}:bf00" "$POOL_DISK2"
```

## ZFS pool creation
#### Create the zpool
```bash
zpool create -f -o ashift=12 \
 -O compression=lz4 \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot mirror "$POOL_DEVICE1" "$POOL_DEVICE2"
```

#### Create initial file systems
```bash
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/${ID}
zfs create -o mountpoint=/home zroot/home

zpool set bootfs=zroot/ROOT/${ID} zroot
```

#### Export, then re-import with a temporary mountpoint of `/mnt`
```bash
zpool export zroot
zpool import -N -R /mnt zroot
zfs mount zroot/ROOT/${ID}
zfs mount zroot/home
```

#### Verify that everything is mounted correctly
```bash
mount | grep mnt
```
```
zroot/ROOT/ubuntu on /mnt type zfs (rw,relatime,xattr,posixacl)
zroot/home on /mnt/home type zfs (rw,relatime,xattr,posixacl)
```

#### Update device symlinks
```bash
udevadm trigger
```

## Install Ubuntu
```bash
debootstrap noble /mnt
```

#### Copy files into the new install
```bash
cp /etc/hostid /mnt/etc
cp /etc/resolv.conf /mnt/etc
```

#### Chroot into the new OS
```bash
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -B /dev /mnt/dev
mount -t devpts pts /mnt/dev/pts
chroot /mnt /bin/bash
```

## Basic Ubuntu Configuration
#### Set a hostname
Example hostname 'nas'
```bash
echo 'nas' > /etc/hostname
echo -e '127.0.1.1\tnas' >> /etc/hosts
```

#### Set a root password
```bash
passwd
```

#### Configure `apt`, use other mirrors if you prefer
```bash
cat <<EOF > /etc/apt/sources.list
## Uncomment the deb-src entries if you need source packages

deb http://no.archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
## deb-src http://no.archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse

deb http://no.archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
## deb-src http://no.archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse

deb http://no.archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
## deb-src http://no.archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse

deb http://no.archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
## deb-src http://no.archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
```

#### Update the repository cache and system
```bash
apt update
apt upgrade
```

#### Install additional base packages
```bash
apt install --no-install-recommends linux-generic locales keyboard-configuration console-setup
```

#### Configure packages to customize local and console properties
```bash
dpkg-reconfigure locales tzdata keyboard-configuration console-setup
```

#### Add additional user packages
```bash
apt install nano net-tools bind9-dnsutils htop btop network-manager git rsync make
```

## Docker
Now let's setup docker
### Add Docker's official GPG key:
```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```
### Add the repository to Apt sources:
```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```
### Install docker packages and test
```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run --rm hello-world
```

## ZFS Configuration
#### Install required packages
```bash
apt install dosfstools zfs-initramfs zfsutils-linux
```

#### Enable systemd ZFS services
```bash
systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target
```

#### Rebuild the initramfs
```bash
update-initramfs -c -k all
```

## Install and configure ZFSBootMenu
#### Set ZFSBootMenu properties on datasets
```bash
zfs set org.zfsbootmenu:commandline="quiet" zroot/ROOT
```

#### Create a `vfat` filesystem
```bash
mkfs.vfat -F32 "$BOOT_DEVICE1"
mkfs.vfat -F32 "$BOOT_DEVICE2"
```

#### Create an fstab entry and mount
```bash
cat << EOF >> /etc/fstab
$( blkid | grep "$BOOT_DEVICE1" | cut -d ' ' -f 2 ) /boot/efi vfat defaults 0 0
EOF

mkdir -p /boot/efi
mount /boot/efi
```

## Install ZFSBootMenu

## Build custom zfs boot menu
Install required packages
```bash
curl -L https://github.com/UsynligAnd/zfsbootmenu/archive/main.tar.gz | tar -zxvf - -C /tmp
mv /tmp/zfsbootmenu-main /etc/zfsbootmenu
```
Add tailscale auth key to `/tmp/zbm-ts-authkey`
```bash
nano /tmp/zbm-ts-authkey
```

### Run build process
```bash
/etc/zfsbootmenu/build.sh
```
### Copy EFI files
```bash
cp /etc/zfsbootmenu/output/zfsbootmenu.EFI /boot/efi/EFI/ZBM/zfsbootmenu.EFI
cp /boot/efi/EFI/ZBM/zfsbootmenu.EFI /boot/efi/EFI/ZBM/zfsbootmenu-backup.EFI
```


#### Configure EFI boot entries
```bash
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
```
```bash
apt install efibootmgr
```
```bash
efibootmgr -c -d "$BOOT_DISK1" -p "$BOOT_PART1" \
  -L "ZFSBootMenu (Backup)" \
  -l '\EFI\ZBM\zfsbootmenu-backup.EFI'

efibootmgr -c -d "$BOOT_DISK1" -p "$BOOT_PART1" \
  -L "ZFSBootMenu" \
  -l '\EFI\ZBM\zfsbootmenu.EFI'
```

## Prepare for first boot
#### Exit the chroot, unmount everything
```bash
exit
```
```bash
umount -n -R /mnt
```
#### Export the zpool and reboot
```bash
zpool export zroot
reboot
```
