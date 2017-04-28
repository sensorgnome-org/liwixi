#!/bin/bash
#
# mkliwixi.sh: generate a liwixi .zip archive that users can unzip to
# a factory-fresh vfat-formatted SD card.  That card will boot directly
# on the Raspberry Pi.
#
# (C) John Brzustowski 2017
#
# Info:   https://github.com/jbrzusto/liwixi
#
# License: CC BY-SA or GPL v 2 or later

BRAND=$1
DEST=$2
TEMP=$3
if [[ -z "$TEMP" ]]; then
    TEMP=$DEST
fi
TEMP=$TEMP/liwixi
mkdir $TEMP
if [[ -z "$DEST" || ! -z "$4" || "$USER" != "root" ]]; then
    cat <<EOF
Usage:

   mkliwixi.sh BRAND DEST [TEMP]

create a .zip archive with a bootable linux image and associated
files that a user can copy to a VFAT SD card to boot a Raspberry Pi.
The file will be called \$DEST/\${BRAND}_LIWIXI.ZIP

BRAND: a string identifying your linux distribution, however you wish
       to do so.  Use embedded whitespace at your own risk.

DEST: the path to a directory which will hold the archive.  It must
      be large enough to store the compressed archive containing
      image and boot files.

TEMP: temporary storage large enough to store the uncompressed image
      and boot files

This script must be run as root.

EOF
    exit 1;
fi
echo <<EOF

I'll make the image big enough to hold the storage *used* by the
current root file system, with an additional 25% to accomodate logfile
growth etc.
EOF

export IMAGE_MB=$(( `df -BM --output=used / | tail -1l | tr -d 'M'` * 5 / 4))

cat <<EOF
This image will occupy $IMAGE_MB M (M = 1024 * 1024 bytes).
Hit enter to continue, or Ctrl-C to quit and do something else...
EOF

read _ignore_

cat <<EOF

Modifying the liwixi script so that it points to your images's
eventual location on the SD card.  The whole initramfs has the simple
job of setting up /dev/loop0 on that image.
EOF

export IMAGE_FILENAME=${BRAND}_LIWIXI_IMAGE_DO_NOT_DELETE
cat ./liwixi | sed -e "s/@@LIWIXI_IMAGE_FILENAME@@/$IMAGE_FILENAME/" > /etc/initramfs-tools/scripts/local-premount/liwixi

echo "Generating an initramfs in $TEMP"

export INITRAMFS=${BRAND}_LIWIXI_INITRAMFS_DO_NOT_DELETE
mkinitramfs -o $TEMP/$INITRAMFS

echo "Generating the image file in $TEMP"

dd if=/dev/zero bs=1M count=${IMAGE_MB} of=$TEMP/$IMAGE_FILENAME
LOOPDEV=`losetup -f`
losetup $LOOPDEV $TEMP/$IMAGE_FILENAME
mkfs -t ext4 $LOOPDEV
mkdir /tmp/$IMAGE_FILENAME
export IMAGE_MOUNT_POINT=/tmp/$IMAGE_FILENAME
mount $LOOPDEV $IMAGE_MOUNT_POINT
rsync -a --exclude='/proc/**' --exclude'=/sys/**'  --exclude='/var/run/**' \
         --exclude='/tmp/**'  --exclude'=/boot/**' --exclude='/media/**'   \
         --exclude='/mnt/**'  --exclude'=/run/**'  --exclude='/dev/**'     \
         / $IMAGE_MOUNT_POINT

echo "Fixing the fstab entry for the root device"

sed -i -e '/ \/ /s/^[^ ]*/\/dev\/loop0/' $IMAGE_MOUNT_POINT/etc/fstab

cat <<EOF

You should verify that the new etc/fstab
shows /dev/loop0 as the device on which '/' is mounted
Here's the new fstab:
EOF
cat  $IMAGE_MOUNT_POINT/etc/fstab

echo <<EOF

Hit enter to continue, or Ctrl-C to quit and fix this script...
EOF

read _ignore_

echo "Okay, proceeding to create the .zip archive"

# unmount the image
umount $IMAGE_MOUNT_POINT
losetup -d $LOOPDEV

echo <<EOF
Adding a line to config.txt in $TEMP
so that it loads the initramfs
EOF

cp /boot/config.txt $TEMP/
echo "initramfs $INITRAMFS" >> $/TEMP/config.txt

echo <<EOF
Changing the kernel command line in cmdline.txt in $TEMP
so it that uses the new image as its root filesystem.
EOF

cat /boot/cmdline.txt | sed -e 's/ root=[^ ]+ / root=/dev/loop0 /' > $TEMP/cmdline.txt

echo <<EOF

Creating the liwixi archive using zip; you're of course free to use a
better program to create a smaller archive if you are willing to teach
your users how to extract it!
EOF

export ARCHIVE=${BRAND}_LIWIXI.ZIP

pushd /boot
echo <<EOF

1. Archiving files from the /boot directory, except for cmdline.txt and
   config.txt for which we already have modified copies,
   and liwixi, in case you're using /boot as temporary storage.
EOF
zip -r ${DEST}/$ARCHIVE . -x ${ARCHIVE} -x cmdline.txt -x config.txt -x "*liwixi*" -x "*LIWIXI*"
cd $TEMP
echo <<EOF

2. Archiving image and initramfs files from $TEMP
EOF
zip -m ${DEST}/$ARCHIVE * -x ${ARCHIVE}
popd
rmdir $TEMP
echo Done:
ls -al ${DEST}/$ARCHIVE
