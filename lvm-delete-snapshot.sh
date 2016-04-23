#!/bin/bash
VERSION="3.2 [02 Sep 2015]"
THIS=`basename $0`
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
while getopts ":fhw" optname; do
    case "$optname" in
		"f")	FORCE="y";;
                "h")    HELP="y";;
                "w")    COLUMNS=30000;; #suppress line-breaking
                "?")    echo "Unknown option $OPTARG"; exit 1;;
                ":")    echo "No argument value for option $OPTARG"; exit 1;;
                *)      # Should not occur
                        echo "Unknown error while processing options"; exit 1;;
    esac
done
shift $(($OPTIND-1))
echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -z "$1" -o -n "$HELP" ]; then
	echo -e "GNU/Linux script for a machine where LVM (Logical Volume \
Management) is used. It removes/deletes an LVM snapshot, and can be called \
by another process or used when a snapshot has been unintentionally left over \
by another process. \
It tries various escalating steps to remove the snapshot; in rare cases the \
removal might not be completed until after a reboot and \
then a rerun of $THIS.

For safety reasons, $THIS will refuse to remove the specified object \
if it is not an LVM snapshot.

It also removes the mountpoint for the snapshot, if one exists.

You can find the name of your snapshot with the command 'sudo lvs'.

Tested under LVM 2.02.66(2), 2.02.95(2), 2.02.98(2).

Options     :
-f - don't ask before proceeding - use with care!
-h - show help and exit

Example     : sudo ./$THIS homebackup

Exit Codes  : 0 indicates success or no action was required (e.g. no such snapshot exists)
              1 indicates a problem occurred

Dependencies: awk, basename, bash, fold, grep, lvm, stty, umount

License: Copyright 2015 Dominic Raferd. Licensed under the Apache License, \
Version 2.0 (the \"License\"); you may not use this file except in compliance \
with the License. You may obtain a copy of the License at \
http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable \
law or agreed to in writing, software distributed under the License is \
distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY \
KIND, either express or implied. See the License for the specific language \
governing permissions and limitations under the License.
"|fold -s -w $COLUMNS
	exit
fi
[ "$(id -u)" != "0" ] && echo -e "Error: $THIS must be run as root\n">&2 && exit 1
SNAPSHOTNAME=$1
if [ "`echo "$SNAPSHOTNAME"|awk -F/ '{print NF}'`" != "1" ]; then
	echo "Invalid name '$SNAPSHOTNAME': should not contain any slashes. Aborting...">&2
	exit 1
fi

# find the LV devicepath and check it is a unique snapshot

# this approach [1] is more elegant but does not work for LVM 2.02.66(2) (2010-05-20)
# because lv_path is not supported in lvs - it does work for 2.02.95(2) (2012-03-06)
#DATA=(`lvs -o lv_attr,lv_path --noheadings|grep "^  [sS].*/$SNAPSHOTNAME$"`)
#[ -z "${DATA[0]}" ] && { echo "Unable to find $SNAPSHOTNAME as a snapshot logical volume, no action required"; exit 0; }
#[ -n "${DATA[2]}" ] && { echo "Found more than one $SNAPSHOTNAME as snapshot logical volumes, aborting...">&2; exit 1; }
#DEVICEPATH="${DATA[1]}"

# this approach [2] works for both versions, but because it uses lvdisplay is more likely
# to break in later versions of LVM
DEVICEPATH=(`lvdisplay 2>/dev/null|grep -E "^  LV (Name|Path).*/$SNAPSHOTNAME$"|awk '{print $3}'`)
[ -n "${DEVICEPATH[1]}" ] && { echo "Found more than one $SNAPSHOTNAME as snapshot logical volumes, aborting...">&2; exit 1; }
[ -z "$DEVICEPATH" ] && { echo "$SNAPSHOTNAME does not exist as a logical volume, no action required"; exit 0; }
ISSNAPSHOT="`lvs 2>/dev/null|grep "^  $SNAPSHOTNAME "|awk '{print substr($3,1,1)}'`"
if [ "$ISSNAPSHOT" != "s" -a "$ISSNAPSHOT" != "S" ]; then
	echo -e "$SNAPSHOTNAME found as LV '$DEVICEPATH', but it is not a snapshot\nPlease check with 'sudo lvs'\nAborting...">&2
	exit 1
fi
# end of approach [2]

# LV path should be something like /dev/myvg/mylv
[ "`echo $DEVICEPATH|awk -F/ '{print NF}'`" != "4" ] && { echo "An unknown error occurred, aborting...">&2; exit 1; }
echo "Identified '$SNAPSHOTNAME' as LVM snapshot logical volume '$DEVICEPATH'"

if [ -z "$FORCE" ]; then
	read -p "About to delete '$SNAPSHOTNAME', are you sure (y/-)? " -t 20
	[ "$REPLY" != "y" -a "$REPLY" != "Y" ] && { echo "Aborting...">&2; exit 1; }
fi
lvremove -f $DEVICEPATH 2>/dev/null
[ $? -eq 0 ] && { echo "Successfully removed '$SNAPSHOTNAME' using lvremove -f"; [ -d /mnt/"$SNAPSHOTNAME" ] && rm -rf /mnt/"$SNAPSHOTNAME"; exit 0; }
echo -e "Unable to do lvremove -f at first attempt, will try to umount"
umount $DEVICEPATH || umount $DEVICEPATH -l
ERR=$?
if [ $ERR -eq 0 ]; then
	echo "Successfully umounted '$SNAPSHOTNAME'"
else
	echo "Umount failed with error $ERR"
fi
if [ "`grep $SNAPSHOTNAME /etc/mtab`" != "" ]; then
	echo -e "Unknown error: unable to umount $DEVICEPATH - it is listed in mtab\nAborting...">&2
	exit 1
fi
[ -d /mnt/"$SNAPSHOTNAME" ] && rm -rf /mnt/$SNAPSHOTNAME
echo -en "lvremove -f [2nd attempt]: "
lvremove -f $DEVICEPATH 2>/dev/null
[ $? -eq 0 ] && echo -e "All seems OK" && exit 0
VGNAME=`echo $DEVICEPATH|awk -F/ '{print $3}'`
echo -en "FAIL\nTrying with dmsetup\ndmsetup remove -f $VGNAME-$SNAPSHOTNAME: "
dmsetup remove -f $VGNAME-$SNAPSHOTNAME
[ $? -eq 0 ] && echo -e "OK\nAll seems OK" && exit 0
echo -en "FAIL\nlvchange -an with lvremove -f: "
lvchange -an $DEVICEPATH && lvremove -f $DEVICEPATH 2>/dev/null
[ $? -eq 0 ] && echo -e "All seems OK" && exit 0
echo "FAIL"
echo "Unable to remove '$SNAPSHOTNAME', please reboot then try again.">&2
exit 1
