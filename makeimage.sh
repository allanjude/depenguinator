#!/bin/sh

if ! [ $# = 3 ]; then
  echo "usage: $0 disc1.iso 10.1-RELEASE ~/.ssh/authorized_keys"
  exit 1
fi

if ! [ `id -g` = "0" ]; then
  echo "You must be root to run this."
  exit 1
fi

# Mount the release ISO image
mkdir dist
rm -f dist.mounted
case "`uname -s`" in
  FreeBSD)
    case "`uname -r`" in
      4*) vnconfig vn0c $1
          mount -t cd9660 /dev/vn0c dist
          touch dist.mounted;;
      5*) mdconfig -a -t vnode -f $1
          mount -t cd9660 /dev/md0 dist
          touch dist.mounted;;
      6*) mdconfig -a -t vnode -f $1
          mount -t cd9660 /dev/md0 dist
          touch dist.mounted;;
    esac;;
  Linux)
    mount -t iso9660 -o loop $1 dist
    touch dist.mounted;;
esac
if ! [ -e dist.mounted ]; then
  echo "Cannot unmount $1 from dist automatically."
  echo "Do it yourself."
  sh -i
  touch dist.mounted
fi

# Extract bits from the release
mkdir mfs && chown 0:0 mfs
cat dist/$2/base/base.?? | bsdtar --unlink -xpzf - -C mfs
cat dist/$2/kernels/generic.?? | bsdtar --unlink -xpzf - -C mfs/boot
rmdir mfs/boot/kernel && mv mfs/boot/GENERIC mfs/boot/kernel

# Unmount the release ISO image
case "`uname -s`" in
  FreeBSD)
    case "`uname -r`" in
      4*) umount dist
          vnconfig -u vn0c
          rm dist.mounted;;
      5*) umount dist
          mdconfig -d -u 0
          rm dist.mounted;;
      6*) umount dist
          mdconfig -d -u 0
          rm dist.mounted;;
    esac;;
  Linux)
    umount dist
    rm dist.mounted;;
esac
if [ -e dist.mounted ]; then
  echo "Cannot unmount $1 from dist automatically."
  echo "Do it yourself."
  sh -i
  rm dist.mounted
fi
rmdir dist

# Clean up files we don't need in the image
rm -rf mfs/rescue
rm -rf mfs/usr/include
for x in c++ g++ CC gcc cc yacc byacc			\
	addr2line ar as gasp gdb gdbreplay ld nm	\
	objcopy objdump	ranlib readelf size strip; do	\
	rm -f mfs/usr/bin/$x;				\
done
rm -f mfs/usr/lib/*.a
rm -f mfs/usr/libexec/cc1*
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
