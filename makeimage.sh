#!/bin/sh

if ! [ $# = 3 ]; then
  echo "usage: $0 10.1-RELEASE ~/.ssh/authorized_keys"
  exit 1
fi

if ! [ `id -g` = "0" ]; then
  echo "You must be root to run this."
  exit 1
fi

#Download the dist set
mkdir dist
rm -f dist.mounted

which fetch 2>&1 > /dev/null
if [ $? -eq 1 ]; then
	which wget 2>&1 > /dev/null
	if [ $? -eq 1 ]; then
		which curl 2>&1 > /dev/null
		if [ $? -eq 1 ]; then
			echo "Please install wget or curl to download FreeBSD"
			exit 3
		fi
		curl -o dist/base.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/base.txz
		curl -o dist/kernel.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/kernel.txz
	else
		wget -O dist/base.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/base.txz
		wget -O dist/kernel.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/kernel.txz
	fi
else
	fetch -o dist/base.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/base.txz
	fetch -o dist/kernel.txz ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/$1/kernel.txz
fi

# Extract bits from the release
mkdir mfs && chown 0:0 mfs
tar --unlink -xpJf dist/base.txz -C mfs
tar --unlink -xpJf dist/kernel.txz -C mfs/boot

#Remove debugging symbols to save space
rm -f mfs/boot/kernel/*.symbols

# Move tar and bits it needs into /
mv mfs/usr/bin/tar mfs/bin/tar
mv mfs/usr/bin/bsdtar mfs/bin/bsdtar
mv mfs/usr/lib/libbz2* mfs/lib
mv mfs/usr/lib/libarchive* mfs/lib

# Move grep and bits it needs into /
mv mfs/usr/bin/grep mfs/bin/grep
mv mfs/usr/lib/libgnuregex* mfs/lib

# Set up script to unpack /usr on boot
cp mdinit mfs/etc/rc.d
chmod 555 mfs/etc/rc.d/mdinit

# Set up rc.conf
cat mdinit.conf depenguinator.conf rcconfglue > mfs/etc/rc.conf

# Set up fake fstab
echo "/dev/md0 / ufs rw 0 0" > mfs/etc/fstab

# Set up bits so that we can SSH in as root.
mkdir mfs/root/.ssh
cp $3 mfs/root/.ssh/authorized_keys
echo PermitRootLogin yes >> mfs/etc/ssh/sshd_config

# Load configuration data
. `pwd`/depenguinator.conf

# Set up /etc/resolv.conf
echo nameserver ${depenguinator_nameserver} > mfs/etc/resolv.conf

# Set up /etc/hosts
echo 127.0.0.1 localhost > mfs/etc/hosts
for interface in ${depenguinator_interfaces}; do
	ipaddr=`eval echo "\\$depenguinator_ip_${interface}"`
	echo ${ipaddr} ${hostname} >> mfs/etc/hosts
	echo ${ipaddr} ${hostname}. >> mfs/etc/hosts
done

# Package up /usr into usr.tgz
( cd mfs && bsdtar -czf usr.tgz usr)
chattr -R -i mfs/usr && rm -r mfs/usr && mkdir mfs/usr

# Build makefs
tar -xzf makefs-20080113.tar.gz
( cd makefs-20080113 && sh -e build.sh )
MAKEFS=makefs-20080113/netbsdsrc/tools/makefs/makefs

# Collect together the bits which go into the root disk
mkdir disk && chown 0:0 disk
cp -rp mfs/boot disk/boot
rm -rf mfs/boot/kernel
${MAKEFS} -b 8% -f 8% disk/mfsroot mfs
gzip -9 disk/mfsroot
gzip -9 disk/boot/kernel/kernel
cp loader.conf disk/boot/

# Create the image
${MAKEFS} disk.img disk
dd if=bootcode of=disk.img conv=notrunc

# Clean up
chattr -R -i mfs && rm -rf mfs
rm -r disk
rm -rf makefs-20080113
