#!/bin/bash
# script for creating 'home' LV
set -o pipefail
VERSION="1.5 [18 Mar 2016]"
THIS=`basename $0`;echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
VGNAME="timedicer"
PROP=80
WARNTEXT="  WARNING:"
FS="ext4"
WARNINGS=0

while getopts ":dfhln:p:t:" optname; do
	case "$optname" in
		"d") DEBUG=y;;
		"f") FORCE=y;;
		"h") HELP=y;;
		"l") CHANGELOG=y;;
		"p") PROP=$OPTARG;;
		"n") VGNAME="$OPTARG";;
		"t") FS="$OPTARG";;
		"?") echo "Unknown option $OPTARG"; exit 1;;
		":") echo "No argument value for option $OPTARG"; exit 1;;
		*) echo "Unknown error while processing options"; exit 1;;
	esac
done
shift $(($OPTIND-1))
if [ "$HELP" = "y" -o -z "$1" ]; then
	HELP="y"
	echo -e "Usage  : $THIS [option] partition
Example: $0 -p 85 /dev/sdb1

Script to create a 'home' LVM Logical Volume with a given name (default 'timedicer'). \
It automatically creates a Volume Group (VG), makes the specified device a Physical Volume (PV) inside that VG, and \
then allocates a proportion (default ${PROP}%) of the space in that VG (and PV) to a Logical Volume (LV) named 'home' \
which is formatted as specified (default $FS). \
It then copies all existing contents of /home into it (if old /home already contains a lot of data \
this may take a long time), and lastly modifies /etc/fstab so that the new volume mounts at '/home' after rebooting.

It aborts on any error, or if it anticipates any incompatibility or problem.

It is normally run after initial setup of a new TimeDicer Server machine.

Prior to running this script, the specified partition must be marked as type 'lvm'. Example (for /dev/sda3):
# check existing status of /dev/sda
sudo parted /dev/sda print
# toggle lvm status of /dev/sda3
sudo parted /dev/sda toggle 3 lvm
# check again
sudo parted /dev/sda print

Options: -f - don't automatically abort even if incompatibility or problem is found
         -h - show this help and exit
         -l - show changelog and exit
         -p percentage - specify the percentage (0-100, default 80) of total space to be immediately allocated
         -n vgname - specify the name (vgname) to be used for volume group (default timedicer)
         -t fs - specify the filesystem (fs) to be used for home LV (default ext4)
"|fold -sw $COLUMNS
fi
if [ -n "$CHANGELOG" ]; then
	[ -n "$HELP" ] && echo "Changelog:"
	echo -e "\
1.5 [18 Mar 2016]: revise to make GPT-disk compatible
1.4 [25 Oct 2015]: use/add 'noatime' mount option
1.3 [07 Aug 2015]: fix bugs introduced by use of lsblk in 1.2, document -t option
1.2 [17 Jul 2015]: add -p option, chmod /home to 755, add test for enough space
1.1 [29 Jan 2015]: separate initial check for existence of specified partition, add -n option
1.0915: more checking done first!
1.0914: first release"|fold -sw $COLUMNS
	exit
fi
[ -n "$HELP$CHANGELOG" ] && exit 0
[ `id -u` -ne 0 ] && echo "$THIS must be run with sudo or as root" && exit 1
echo "Checking for LVM"
lvm version >/dev/null 2>&1 || { echo "LVM not installed, aborting...">&2; exit 1; }
PARENT="$(echo $1|sed 's/[0-9]*$//')"
PARTNO="$(echo $1|sed 's@/dev/[a-z]*@@')"
echo -e "Checking $PARENT partition $PARTNO exists"
LINESTART=$(parted $PARENT print|grep -n "^Number"|awk -F: '{print $1}')
PARTINFO="$(parted $PARENT print|sed -n "$LINESTART,\${/^ $PARTNO /p}")"
[[ -z $PARTINFO ]] && {	echo "$WARNTEXT $1 is not a partition, aborting...">&2; exit 1; }
echo -e "Checking that LVM Volume Group $VGNAME does not already exist"
for VG in $(vgdisplay -c|sed 's/^ *//;s/\([^:]*\).*/\1/'); do
	[ "$VG" = "$VGNAME" ] && { echo "$WARNTEXT $VG already exists as an LVM Volume Group (VG)" >&2; let WARNINGS++; [ -z "$FORCE" ] && echo "  aborting" && exit 1; }
done
echo -e "Checking that LVM Physical Volume $1 does not already exist"
for PV in $(pvs --noheadings -o pv_name); do
	[ "$PV" = "$1" ] && { echo "$WARNTEXT $PV already used as an LVM Physical Volume (PV)" >&2; let WARNINGS++; [ -z "$FORCE" ] && echo "  aborting" && exit 1; }
done
echo -e "Checking that LVM Logical Volume /dev/$VGNAME/home does not already exist"
for LV in $(lvs --noheadings -o lv_path); do
	[ "$LV" = "/dev/$VGNAME/home" ] && { echo "$WARNTEXT $LV already used as an LVM Logical Volume (LV)" >&2; let WARNINGS++; [ -z "$FORCE" ] && echo "  aborting" && exit 1; }
done
echo -e "Checking that $1 is not already in use/mounted"
for UUID in $(ls -l /dev/disk/by-uuid|grep ${1/dev/..}$|awk '{print $8}'); do
	for DEV in $UUID $1; do
		for FILE in /etc/fstab /etc/mtab; do
			#echo checking $DEV in $FILE
			INUSE=`sed -n "s/#.*//;s@$DEV@$DEV@p" "$FILE"`
			[ -n "$INUSE" ] && { echo -e "$WARNTEXT $1 is currently in use as $DEV and listed in $FILE:\n  $INUSE" >&2; let WARNINGS++; [ -z "$FORCE" ] && echo "  aborting" && exit 1; }
		done
	done
done
HOMEUSED="$(df -h --output=used /home|tail -n1)iB"
echo "Space currently in use on mount of volume containing /home:$HOMEUSED"
echo "Checking there will be enough space on $PROP% of $1"
HOMEUSEDB="$(df -B1 --output=used /home|tail -n1)"
HOMENEWSECTORSIZE=$(blockdev --getss "$PARENT")
HOMENEWSECTORCOUNT=$(blockdev --getsz "$PARENT")
HOMENEWB="$(($HOMENEWSECTORSIZE * $HOMENEWSECTORCOUNT ))"
# for safety we require 1GiB overhead tho obvs this is not really enough
[[ $(($HOMENEWB*$PROP/100-$HOMEUSEDB)) -gt 1073741824 ]] || { echo -e "Insufficient space using ${PROP}% of $1:\n  we need minimum$HOMEUSED + 1GiB, we will have only $(( $PROP*$HOMENEWB/107374182400 ))GiB">&2; let WARNINGS++; [ -z "$FORCE" ] && echo "  aborting" && exit 1; }

[ $WARNINGS -gt 0  ] && echo -e "\n$WARNINGS warnings issued: it is dangerous to proceed!" || echo -e "All checks completed successfully, no problems identified\n"
echo -e "Note: all data will be copied from current /home - and if /home already has a lot of data this may take a long time. Please ensure that /home is not written to during this period or the new /home may have inconsistent data."|fold -sw $COLUMNS
read -t 20 -p "Create $FS LV /dev/$VGNAME/home using $1. Continue - last chance [yes/-]? "
[ "$REPLY" != "yes" ] && { echo "  User didn't reply with 'yes', aborting, no changes made...">&2; exit 1; }
if [[ $(echo "$PARTINFO"|awk '{printf $NF}') != "lvm" ]]; then
	echo "Marking $1 with lvm flag"
	parted $PARENT toggle $PARTNO lvm || { echo "  Operation failed, aborting..." >&2; exit 1; }
fi
echo -e "Creating $1 as an LVM Physical Volume (PV)"
pvcreate $1
[ $? -gt 0 ] && { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nCreating LVM Volume Group '$VGNAME' with PV $1"
vgcreate $VGNAME $1
[ $? -gt 0 ] && { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nObtaining size of Volume Group"
AVAILABLE=$(vgs --noheadings 2>/dev/null|awk '{print toupper($NF)}' 2>/dev/null)
[ -z "$AVAILABLE" ] && { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nCalculating size for Logical Volume 'home'"
SUGGESTED=$(echo $AVAILABLE|awk -v PROP="$PROP" '{print int(PROP*$NF/100) toupper(substr($NF,length($NF),1)) }')
[ -z "$SUGGESTED" ] && { echo "  Operation failed, aborting...">&2; exit 1; }
echo "Available space: $AVAILABLE, will use ${PROP}% for home: $SUGGESTED"
lvcreate -L $SUGGESTED -n home $VGNAME
[ $? -gt 0 ] && { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nFormatting /dev/$VGNAME/home as ext4"
mkfs -t $FS /dev/mapper/$VGNAME-home || { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nSaving LVM settings"
vgscan || { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nMounting the new home temporarily"
mkdir -p /mnt/newhome
mount -o noatime /dev/$VGNAME/home /mnt/newhome || { echo "  Operation failed, aborting...">&2; exit 1; }
# allow users to traverse the new /home but only root can change its attributes
echo -e "  ... success\nChmodding /home to rwxr-xr-x"
chmod 755 /mnt/newhome || { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nCopying existing /home data to new home"
cp -a /home/* /mnt/newhome || { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nUnmounting the new home"
umount /mnt/newhome || { echo "  Operation failed, aborting...">&2; exit 1; }
echo -e "  ... success\nModifying /etc/fstab"
# comment out any existing /home mount
sed -i '/^[^#].*\s\/home\s/s/^/#/' /etc/fstab || { echo "  Operation 1/2 (sed) failed, aborting...">&2; exit 1; }
# add new /home mount
echo "/dev/mapper/$VGNAME-home /home ext4 rw,noatime 0 0" >>/etc/fstab || { echo "  Operation 2/2 (echo) failed, aborting...">&2; exit 1; }
echo -e "  ... success\nOperation to make new 'home' using $1 has completed, please reboot now"
