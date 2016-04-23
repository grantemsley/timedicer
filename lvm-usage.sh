#!/bin/bash
# lv-usage.sh
# ------------------
VERSION="4.30 [18 Mar 2016]"
THIS="`basename $0`"
COLUMNS="$(stty size 2>/dev/null||echo 80)"; COLUMNS=${COLUMNS##* }
while getopts ":dfhilqw" optname; do
    case "$optname" in
		"d")	DEBUG="y";;
		"f")	FULL="y";;
		"h")	HELP="y";;
		"i")	ASCII="-i";;
		"l")	CHANGELOG="y";;
		"q")	QUIET=1;;
		"w")	COLUMNS=30000;; #suppress line-breaking
		"?")	echo "Unknown option $OPTARG"; exit 1;;
		":")	echo "No argument value for option $OPTARG"; exit 1;;
		*)	# Should not occur
			echo "Unknown error while processing options"; exit 1;;
    esac
done
shift $(($OPTIND-1))
[ -z "$QUIET" ] && echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -n "$HELP" ];then
	echo -e "For GNU/Linux systems using LVM (Logical Volume Management), \
shows usage of:
- LVM Physical Volumes (PVs)
- LVM Volume Groups (VGs)
- LVM Logical Volumes (LVs)

And for all systems (using LVM or not) it shows usage of:
- Mounted filesystems
- Physical disk partitions

It also gives a localised example showing how space could be added using \
LVM and, with the \
'-f' option,  analyses usage of /home in a tree format. When run with \
'-q' option it will be silent unless any filesystem's level of usage \
is over the specified percent_trigger, and so it can be used to issue \
a warning if running out of space.

Suggested use is as a cron job with e.g. -q 75 (percent_trigger is ignored \
without -q switch.) Note that if run with '-f' option it can take many \
minutes to complete.

All sizes are reported in binary quantities e.g. gibibytes i.e. powers of \
1024 not 1000.

Oh, and it runs happily on systems that do not have or use LVM, too.

Usage       : $THIS [options] [percent_trigger]

Example     : sudo ./$THIS -q 85

Options     : -f  full (show full tree usage of /home)
              -h  shows these instructions and exit
              -i  use ascii characters for tree
              -l  show changelog and exit
              -q  suppress output unless usage is over percent_trigger (default 0%)

Dependencies: awk bash coreutils grep linux-utils parted sed util-linux_(for_lsblk)

License: Copyright 2016 Dominic Raferd. Licensed under the Apache License, \
Version 2.0 (the \"License\"); you may not use this file except in compliance \
with the License. You may obtain a copy of the License at \
http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable \
law or agreed to in writing, software distributed under the License is \
distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY \
KIND, either express or implied. See the License for the specific language \
governing permissions and limitations under the License.
"|fold -s -w $COLUMNS
fi
if [ -n "$CHANGELOG" ];then
	[ -n "$HELP" ] && echo "Changelog:"
	echo -e "\
4.30 [18 Mar 2016] - remove all use of fdisk to make GPT-disk-compatible
4.26 [14 Dec 2015] - don't warn about 'full' iso9660 fs
4.25 [22 Sep 2015] - add -i option
4.24 [18 Aug 2015] - fix some PATH problems on some os (e.g. Centos 5), \
restore ability to work without lsblk (also missing on Centos 5)
4.23 [21 Jul 2015] - add swap info and include all filesystems
4.22 [20 Jul 2015] - output layout improvement
4.21 [04 May 2015] - corrected/simplified list of dependencies
4.20 [04 Apr 2015] - consistently use powers of 1024, lsblk instead of fdisk
4.14 [16 Mar 2015] - simplified/improved resizing example
4.13 [26 Feb 2015] - add example for resizing with btrfs
4.12 [21 Feb 2015] - minor layout improvement
4.11 [03 Feb 2015] - include tmpfs filesystems in report
4.10 [16 Jan 2015] - use mktemp, recreate/mount /tmp read-write if it is currently read-only
4.03 [05 Mar 2014] - remove extraneous sudo
4.02 [02 Mar 2014] - improved layout
4.0110 [10 Jan 2014] - minor fix
3.1117 [17 Nov 2013] - also exclude tmpfs & devtmpfs \
filesystems, add listing of physical partitions
3.0611 [11 June 2013] - also exclude shmfs filesystems
2.0807 [07 Aug 2012] - also exclude ecryptfs filesystems from output
2.0717 [17 Jul 2012] - minor correction for output wording
2.0513 [13 May 2012] - improved example text
2.0430 [30 Apr 2012] - when analysing /home, show files + directories over 1GB
2.0426 [26 Apr 2012] - improved example text
2.0417 [19 Apr 2012] - improved localised example for adding PV to VG
2.0412 [12 Apr 2012] - correctly remove temporary files in quiet mode
2.0219 [19 Feb 2012] - work smoothly if no LVM-mapped filesystems, bugfix, improved help, rename as 'lvm-usage.sh'
2.0216 [16 Feb 2012] - change -f fast option to -f full
2.0214 [14 Feb 2012] - exclude 'iso9660', include 'none' filesystems
2.0209 [09 Feb 2012] - provide localised examples in help text, add listing and checking of non-LVM filesystems
2.0125 [25 Jan 2012] - minor correction in help text
2.0117 [17 Jan 2012] - trivial elucidation in help text
2.0106 [06 Jan 2012] - fix for VG containing dash in name, add -f option
1.1231 [31 Dec 2011] - changed text
"|fold -s -w $COLUMNS
fi
[ -n "$HELP$CHANGELOG" ] && exit 0

# in some systems the path requirements may not be met
for PATHREQ in /sbin /usr/sbin; do
	[[ -z $(echo $PATH|awk -F: -v PATHREQ=$PATHREQ '{for (i=1;i<=NF;i++) {if ($i==PATHREQ) print $i}}') ]] && PATH="$PATH:$PATHREQ"
done
[[ -n $DEBUG ]] && echo "PATH is: '$PATH'"
if [ "$1" != "" ]; then
	percent_trigger=$1
	shift
else
	percent_trigger=0
fi
# check we are running as root
[ "$(id -u)" != "0" ] && echo -e "Sorry, $THIS must be run as root\n">&2 && exit 1

[ -z "$QUIET" ] && echo -e "Run time: $(date -R)\nAll information in powers of 1024 (i.e. Gibibytes etc)\n"

# check if /tmp is writeable and if not then mount rw
# - useful in recovery mode where /tmp is inside read-only root LVM volume
ROTMP=$(grep "\sro[\s,]" /proc/mounts|grep "$(df --output=source /tmp 2>/dev/null | tail -n1)")
[ -n "$ROTMP" ] && mount -t tmpfs tmpfs /tmp && MADE_RW_TMP="y"

TMPFILE2="$(mktemp)"
# 'mapper' filter picks up LVM volumes, 'Avail' picks up header row,
# sed command remaps the long-form mapping 'dev/mapper/timedicer-home'
# to '/dev/timedicer/home'

# check if any mounted LVM filesystems
[ $(df -TPh 2>/dev/null|sed '2,${/\/dev\/mapper\//!d}'|wc -l) -lt 2 ] && NOLVM="y"
# get list of all filesystems, remove some we are not interested in and make some text changes
df -TPh 2>/dev/null >"$TMPFILE2"
swapon -s|tail -n +2|awk '{printf "%s %s",$1,"swap"; printf " %.1fG %.1fG %.1fG %.0f%% %s\n",$3/(1024^2),$4/(1024^2),($3-$4)/(1024^2),(100*$4/$3),$5}'|sort -rnk8 >>"$TMPFILE2"
#sed -i '2,${/^.* *devtmpfs/d;/^.* *ecryptfs/d;/^.* *iso9660/d;/^.* *shmfs/d;/^.* *rootfs/d;};/^\/dev\/mapper/!{s/ / No /};/^\/dev\/mapper/{s@/mapper@@;s@--@ZZ@g;s@-@/@g;s@ZZ@-@g;s/ / Yes /};1{s/ No / LVM /;s/Avail/Available/;s/%//;s/ed on$/\/Priority/}' "$TMPFILE2"
sed -i '/^\/dev\/mapper/!{s/ / No /};/^\/dev\/mapper/{s@/mapper@@;s@--@ZZ@g;s@-@/@g;s@ZZ@-@g;s/ / Yes /};1{s/ No / LVM /;s/Avail/Available/;s/%//;s/ed on$/\/Priority/}' "$TMPFILE2"

if [ -n "`awk -v trig=$percent_trigger '{if ( NR>1 && substr($7,1,length($7)-1)+0 >= trig && $3!="iso9660" ) print 1 }' $TMPFILE2`" ]; then
	[ $percent_trigger -gt 0 ] && echo -e "Warning! One or more filesystems on `uname -n` is/are ${percent_trigger}% or more full"
	unset QUIET
fi
[ -n "$QUIET" ] && { [ -z "$DEBUG" ] && rm "$TMPFILE2"; exit; }
[ -n "$MADE_RW_TMP" ] && echo -e "Note: created writeable /tmp as tmpfs\n"
# for Physical Volumes and Volume Groups we show 'G' for gigabytes 1024 format - unlike pvs/vgs which use 'G' for 1000 format - our style matches that of df -h
if [ -n "$NOLVM" ]; then
	echo "No LVM-based filesystems found"
else
	TMPLVM=$(mktemp)
	echo -e "LVM:"
	pvs -o pv_name,pv_size,pv_free,vg_name,pv_attr 2>/dev/null|sed '1{s/PV/Physical_Volume(PV)/;s/VG/Volume_Group(VG)/;s/PS/S/;s/PF/F/;};1!{s/\([0-9]\)g\(\b\)/\1G\2/g}' >$TMPLVM
	LASTPVSDRIVE=`pvs 2>/dev/null|tail -n 1|awk '{print substr($1,6,3)}'`
	NEXTPVSDRIVE=${LASTPVSDRIVE:0:2}`printf "\x$((\`echo -n "${LASTPVSDRIVE:2:1}"|od -A n -t x1|awk '{print $1}'\`+1))"`
	if [ -z "`echo "0123456789"|grep -o "${NEXTPVSDRIVE:2:1}"`" ]; then
		# if it is a three-letter drive type e.g. sdb rather than md, add trailing digit
		NEXTPVSDRIVE="${NEXTPVSDRIVE}1"
	fi
	echo >>$TMPLVM
	vgs -o name,size,free 2>/dev/null|sed '1{s/VG/Volume_Group(VG)/;s/VS/S/;s/VF/F/};1!{s/\([0-9]\)g\(\b\)/\1G\2/g}' >>$TMPLVM
	lvs -o lv_path,lv_size,devices,vg_name|sed '1{s/VG/Volume_Group(VG)/;s/LS/S/;s/Path/\nLogical_Volume(LV)/};1!{s/\([0-9]\)g\(\b\)/\1G\2/g}' >>$TMPLVM
	# earlier versions of column don't support -e option (which is: don't ignore blank lines)
	COLUMN_EOPT=$(echo "e"|column -e 2>/dev/null)
	column -${COLUMN_EOPT}t $TMPLVM | sed 's/^/  /'; rm $TMPLVM
fi
echo -e "\nMounted filesystems and swap:"
cat $TMPFILE2|column -t|sed 's/^/  /'
# now show physical partitions of all disks (not LVM)
echo -e "\nPhysical disk partitions:"
if hash lsblk 2>/dev/null; then
	lsblk $ASCII -o NAME,FSTYPE,SIZE,MOUNTPOINT|sed '1{s/.*/\L&/; s/[a-z]*/\u&/g;s/Fstype/Type  /;s/point//};s/^/  /;/sr[0-9]/d'
else
	parted --list 2>/dev/null|grep -E "^Disk /dev/[mhs]d"|awk -F "[ :]" '{print $2}'|xargs -I {} parted {} unit compact print|grep -Ev '^(Model:|Sector|Partition|Disk Flags|$)'|sed 's/File system/Filesystem/'|sed '/Disk */{s/Disk //;s/:/: _ _ /}'|column -t|awk '{if (NR==1) {SAVE1=$0} else if (NR==2) {print $0"\n"SAVE1} else if ($1!="Number") print $0}'|sed '/^\/dev/s/_/ /g;s/^/  /'
fi
if [ -z "$NOLVM" ]; then
	echo -e "\nLocalised example to add space with LVM:"
	# use the first listed VG as example
	EXAMPLEVG="`vgs -o name|sed -n '2s/^ *//p'`"
	[ -z "$EXAMPLEVG" ] && EXAMPLEVG="myvg"
	# use 'home' LV example if it exists, otherwise 'root', otherwise use the first listed LV
	for SEDLV in "/dev\/$EXAMPLEVG\/home/" "/dev\/$EXAMPLEVG\/root/" "2"; do
		#echo "SEDLV: $SEDLV"
		[ -n "$EXAMPLELV" ] && break
		EXAMPLELV=`sed -n "${SEDLV}s/\([^ ]*\).*/\1/p;t" "$TMPFILE2"`
	done
	[ -z "$EXAMPLELV" ] && EXAMPLELV="/dev/$EXAMPLEVG/mylv"
	EXAMPLELVNAME="`basename $EXAMPLELV`"
	echo -e "\
  # This example assumes '/dev/$NEXTPVSDRIVE' exists, is unused and has blank or
  # expendable content.  If 'dev/$NEXTPVSDRIVE' is a partition it should preferably
  # be marked as type lvm e.g. with parted.
  #
  # Initialise '/dev/$NEXTPVSDRIVE' as new PV and add it to VG '$EXAMPLEVG':
    $ sudo vgextend $EXAMPLEVG /dev/$NEXTPVSDRIVE
  # Make sure LVM has the new configuration:
    $ sudo vgscan
  # Allocate 20G free VG space to LV '$EXAMPLELVNAME' & resize filesystem:
    $ sudo lvextend -L+20G -r $EXAMPLELV"
fi
if [ -n "$FULL" ]; then
	echo -e "\nGathering information about /home directories..."
	TMPFILE3=$(mktemp)
  TMPFILE1=$(mktemp)
	echo -e "\nUsage of /home:">$TMPFILE3
	du /home -ah>"$TMPFILE1"
	# unfortunately the version of sort with Ubuntu 10.04 does not support -h
	#cat $TEMP/`basename $0 .sh`-tmp1.txt|awk -F "/" '{if (NF==3) print $0}'|sort -rhb -k 2 >>$TMPFILE3
	cat "$TMPFILE1"|awk -F "/" '{if (NF==3) print $0}'|sort -b -k 2 >>$TMPFILE3
	echo -e "\\nLarge directories in /home (>1G):">>$TMPFILE3
	cat "$TMPFILE1"|grep -E "^[1-9][0-9.]*G"|sort -b -k 2|awk -F "\t|/" '{printf $1 "\t"; x=3; while (x<=(NF-1)) {printf "  "; x++}; x=3; while (x<=NF) {printf "/" $x; x++} print ""}'>>$TMPFILE3
	cat $TMPFILE3
	[ -z "$DEBUG" ] && rm "$TMPFILE3" "$TMPFILE1"
fi
[ -z "$DEBUG" ] && rm "$TMPFILE2"
