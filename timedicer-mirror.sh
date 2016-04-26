#!/bin/bash
#
# timedicer-mirror
# ================
#
# Part of the TimeDicer suite. This program, run from Primary TimeDicer Server,
# syncs a Mirror TimeDicer Server to match the Primary TimeDicer Server.
#
# More generally it mirrors key data + user/group settings from local (source)
# machine to remote (destination) machine using rsync.
#
# For more information run with -h.
#

# Note to self about use of --link-dest: [20 Nov 2015]
# see https://lists.samba.org/archive/rsync//2014-December/029858.html

# Using --link-dest, if a file has not changed on the destination machine, a hard link to it is created
# in the new destination directory (to the same file that is already pointed to in the comparison directory on the
# destination). Suppose the backup that created this hard link subsequently fails and you then run another rsync
# --link-dest session, but in the meantime the source file has had a metadata (but not a file content)
# change (e.g. permissions): now the metadata (permissions etc) will be changed on the destination file and this will immediately affect the underlying file i.e. the one
# in the comparison directory not only the one in the new destination directory.

# this is a technical gotcha because you would not expect the comparison directory data to change at all, yet here it
# can do. However I don't regard it as a a problem for timedicer-mirror because once we have completed a full rsync
# session we will in any case replace the comparison directory contents with those in the new destination directory.
# The issue is more theoretical, especially as it relates only to metadata (if the file contents change, then a new file
# has to be created in the new destination directory anyway and the hard-link to the previous file will be removed, so the
# other copy of the previous file will still exist - for the time being - in the comparison directory).

# another gotcha (bug) existed in rsync --link-dest prior to 3.1.1 which could lead to wasted disk space on the
# destination - this is a reason to use Ubuntu 14.10+ as distro, or rebuild rsync from source - see
# http://unix.stackexchange.com/questions/193308/how-to-get-rsync-to-link-identical-files-with-link-dest-option-if-an-old-file
VERSION="6.0425 [25 Apr 2016]"

function quit () {
  # exit with code $1, but first restart any suspended verification sessions
  #if [ -n "$VERIFYPROCESSES" ]; then
  #	kill -CONT $VERIFYPROCESSES
  #	[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Reactivated rdiff-backup verification processes $VERIFYPROCESSES"
  #fi
  exit $1
}

function check_ssh_connection () {
  # exits with 0 if a valid connection can be made to $1
  # exit code 2 if missing or invalid connect address
  # exit code 1 otherwise
  # example: check_ssh_connection root@192.168.100.130
  # optional parameter $2 is o ('off') to indicate we are seeking a non-zero
  # ssh exit code, 'b' to indicate it should not wait for any particular result
  # but return immediately, otherwise it seeks 0 (i.e. successful connection):
  # so call it with 2nd param o to return a fast result if there is no
  # connection, and w/o 2nd param to return fast result if there is a connection,
  # and with 2nd param b to return a fast result regardless.
  [ -z "$1" ] && return 2
  [ -z "`echo $1|grep -E \".+@.+\"`" ] && return 2
  for i in {1..9}; do
    ssh $SSHOPTS -q -q -o ConnectTimeout=10 $1 "echo 1 >/dev/null"
    # note SSHERR is not local to this function
    SSHERR=$?
    if [ -z "$2" -a $SSHERR -eq 0 ] || [ "$2" = "o" -a $SSHERR -ne 0 ] || [ "$2" = "b" ]; then
    	break
    fi
    [ -z "$QUIET" ] && echo -n "."
  done
  return $SSHERR
}

function test_and_wake_dest() {
# now try to connect to DESTIP
SSH_RETRY="b"
for (( LOOPWOL=1; LOOPWOL<=8; LOOPWOL++ )) do
	[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Testing ssh connection to destination ($LOOPWOL)"
	# first time, give up after one try, on subsequent loops check_ssh_connection will retry connection
	check_ssh_connection root@$DESTIP $SSH_RETRY
	[ -z "$QUIET" ] && echo
	[ "$SSHERR" -eq 0 ] && break	# jump out if connection was successful
	# try waking it
	[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Test ssh connection ($LOOPWOL) failed, now trying to wake destination"
	[ -z "$BACKUP2MAC" ] && { echo "`date +%H:%M:%S` Unable to send magic packet to destination because no valid dest_mac, aborting..." >&2; quit 2; }
	wakeonlan -v >/dev/null 2>&1 || { echo "`date +%H:%M:%S` Unable to send magic packet to destination because wakeonlan program is not installed, aborting..." >&2; quit 2; }
	wakeonlan -p $WAKEPORT -i $DESTIP "$BACKUP2MAC" >/dev/null || { echo "`date +%H:%M:%S` An error occurred when trying to send magic packet to destination $DESTIP $BACKUP2MAC, aborting..." >&2; quit 2; }
	[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Sent magic packet to destination"
	sleep 45
	unset SSH_RETRY
done
if [ "$LOOPWOL" -eq 9 ]; then
	echo "`date +%H:%M:%S` Unable to wake destination $DESTIP $BACKUP2MAC port $WAKEPORT UDP, aborting...">&2
	return 2
elif [ -z "$QUIET" ]; then
	if [ "$LOOPWOL" -gt 1 ]; then
		echo "`date +%H:%M:%S` Successfully woke destination"
	else
		echo "`date +%H:%M:%S` Successfully connected to destination, which was not asleep"
	fi
	return 0
fi
}

function puttosleep () {
# attempt to poweroff $DESTIP
  [ -n "$NOSLEEP" ] && return
  [ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Powering off destination machine"
  ssh $SSHOPTS root@$DESTIP poweroff 2>/dev/null
  if [ $? -eq 0 ]; then
    sleep 20s
    check_ssh_connection root@$DESTIP o
    if [ $SSHERR -gt 0 ]; then
      [ -z "$QUIET" ] && echo -e "\n`date +%H:%M:%S` Confirmed that destination is powered off"
    else
      [ -z "$QUIET" ] && echo -e "\n`date +%H:%M:%S` Attempted to power off destination, but can still make ssh connection..."
      return 1
    fi
  else
    [ -z "$QUIET" ] && echo -e "\n`date +%H:%M:%S` Attempted to power off destination, but could not connect to it..."
    return 1
  fi
}

function valid_ipv4 () {
  # return status 0 if param1 seems a valid dotted decimal ipv4, otherwise 1. No text output. Version 1.40914
  # Example usage: valid_ip4 $ip || echo "'$ip' is not a valid ip"
  # Note:          returns 1 for unusual formats e.g. leading zeroes (032.013.123.345) or with spaces (19. 23.  3.100)
  return $(( 1 - $(echo -n "$1." | grep -cE "^(0\.|[1-9][0-9]{0,2}\.){4}$") ))
}


#check we are running under bash
[ -z "$BASH_VERSION" ] && echo "Sorry, this must be run under bash shell.">&2 && exit 1
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
THIS=`basename $0`

# RSYNCADDOPTIONS:
# note: --append-verify is incompatible with --in-place and (probably) ignored when --link-dest is used; a pity
#       as I think rsync could run faster with --in-place by making a local copy of the file at destination's link-dest,
#       and then update date it by appending, then test it with checksum and only if that fails have to transfer
#       the whole file from source. But it doesn't seem to work this way.

# return rsync version as a six digit number vvwwxx i.e. 30102 for 3.1.2
RSYNCVER=$(rsync --version|awk -F"[ .]*" '{if (NR==1) printf "%u%02u%02u",$3,$4,$5+0}')
RSYNCADDOPTIONS="-a --partial --partial-dir=.rsync-partial --timeout=1800 --fuzzy -hh --stats --exclude \".cache/\""

# SSHOPTS:
# note the use of StrictHostKeyChecking=no means that ssh does not confirm the validity of the destination
# fingerprint, it auto-accepts it (and will accept future connections to same destination.) This behaviour makes life
# easier if the destination address might change, at the price of reducing security.
# note also the setting of ServerAliveInterval. ServerAliveCountMax is 3 (default) so a disconnect will happen if the
# remote machine fails to respond within 30 minutes (this is more or less the same time as the rsync timeout 1800).
SSHOPTS="-o PasswordAuthentication=no -o StrictHostKeyChecking=no -o ServerAliveInterval=600"
SSHPORT=22
WAKEPORT=9
NOSLEEP="y"

while getopts ":abcdefhik:lm:nop:qrstuvwz" optname; do
  case "$optname" in
    "a") 	RSYNCADDOPTIONS="--progress --out-format=%t_%l_%b_%n $RSYNCADDOPTIONS"; VERBOSE="-v"; ACTIVE="y";;
    "b")	BIDIRECTIONAL="y";;
    "c")	RSYNCADDOPTIONS="-c $RSYNCADDOPTIONS";CHECKSUM="y";;
    "d")	DEBUG="y";;
    "e")	NOSNAP="y";;
    "f")	FAST="y"; MODIFIERLC="fast "; MODIFIERTC="Fast ";;
		# add options to backup hidden folder e.g. /home/.ssh
		# but not to delete other files
		# RSYNCADDOPTIONS="--include=/*/ --include=/*/.** --exclude=/** `echo $RSYNCADDOPTIONS|sed 's/--delet[^ ]*//;g'`";;
    "h")	HELP="y";;
    "i")	IGNORESPACECHECK="y";;
    "k")	WAKEPORT="$OPTARG";;
    "l")	CHANGELOG="y";;
    "m")	MACADDR="$OPTARG";;
    "n")	unset NOSLEEP;;
    "o")	NOSPACECHECKS="y";;
    "p")	SSHOPTS="-p $OPTARG $SSHOPTS"; SSHPORT="$OPTARG";;
    "q")	QUIET="y"; RSYNCADDOPTIONS="-q $RSYNCADDOPTIONS";;
    "r")	RESTART="y";;
    "s")	STOP="y";;
    "t")	TEST="y"; MODIFIERLC="test "; MODIFIERTC="Test ";;
    "u")	USEEXISTINGSNAPSHOT="y";;
    "v") 	RSYNCADDOPTIONS="-v --out-format=%t,%l,%b,\"%n\" $RSYNCADDOPTIONS"; VERBOSE="-v";;
    "w")	COLUMNS=30000;; #suppress line-breaking
    "z")	COMPRESS="y"; [[ $RSYNCVER -lt 30101 ]] && RSYNCADDOPTIONS="-z $RSYNCADDOPTIONS" || RSYNCADDOPTIONS="-zz $RSYNCADDOPTIONS";; # use new-style (3.1.1) compression if available
    "?")	echo "Unknown option $OPTARG">&2; exit 1;;
    ":")	echo "No argument value for option $OPTARG">&2; exit 1;;
    *)		# Should not occur
		echo "Unknown error while processing options">&2; exit 1;;
  esac
done
shift $(($OPTIND-1))
# add ssh options to rsync options
export RSYNC_RSH="ssh $SSHOPTS"

if [ -z "$QUIET" ];then
  echo -e "\n$THIS v$VERSION by Dominic\n${THIS//?/=}\n"
fi
[ -n "$DEBUG" ] && echo -e "RSYNC_RSH: '$RSYNC_RSH'\nRSYNCADDOPTIONS: '$RSYNCADDOPTIONS'\nSSHOPTS: '$SSHOPTS'"

if [ -n "$HELP" ]; then
	echo -e "\
$THIS mirrors (synchronises) critical data from a local (source) machine \
to a remote (destination) machine using rsync and other tools. \
It is part of the TimeDicer suite (http://www.timedicer.co.uk); \
its purpose is to update the rdiff-backup repositories, and other \
TimeDicer-specific setings, of a Mirror TimeDicer to be the same as those \
on a Primary TimeDicer Server. It is always run from the sending machine (Primary).

On the remote (destination) machine $THIS creates any missing users (ID>1000) \
and groups, \
and it mirrors the file /etc/rdiffweb/rdw.db (if found) and the directories \
/opt and /home. (It does not mirror the operating system.) Copies of \
/etc/crontab and /etc/rc.local are placed in \
source machine's /opt before it is mirrored to remote /opt.

The drawn-out part of the task is mirroring /home. $THIS ensures that all new \
/home data is successfully transferred to the remote machine before \
any of the old data there is replaced. Only after successful transfer of all \
new data is the old /home data on the remote machine replaced with the new. \
Failed sessions, \
say caused by internet connection problems, may delay the updating of the \
remote machine but should not corrupt its data.

Tested under Ubuntu Server 14.04LTS and designed for use \
as a nightly cron job with TimeDicer Server.

Usage  : $THIS [options] dest_address
Example: sudo /opt/$THIS -v 192.168.100.130

Options:
  -a: active progress mode - shows file transfer progress, implies verbose
  -b: permit bidirectional backup (i.e. don't abort if there are users \
already on destination that don't exist on source, as long as there are \
no name/uid/gid conflicts)
  -c: determine if file backup is needed by checksum rather than \
comparing file date, time & size, and also compare usage of /home on source \
and destination (much slower)
  -e: force no snapshot - backup directly from /home not from a snapshot \
created using btrfs or LVM, even if such is possible
  -f: fast mode - don't check space on destination machine and don't \
backup /home (see -o)
  -h: show help and exit
  -i: check space on destination machine as normal, but ignore results (see \
also -o)
  -k num: specify remote WOL UDP port 'num' (default 9; see also -m)
  -l: show changelog and exit
  -m macid: specify MAC address of destination machine - if asleep a WOL \
'magic packet' will be sent to wake it (see also -k)
  -n: poweroff destination machine at end ('night night')
  -o: don't check space on destination machine - faster (see -i, -f)
  -p num: specify destination SSH TCP port 'num' (default 22)
  -q: quiet mode - no output unless there is a problem
  -r: restart i.e. stop any prior instance, then continue
  -s: stop any prior running instance of this program
  -t: test mode - no changes on destination (see also -f)
  -u: use pre-existing mounted source snapshot (e.g. as left behind after \
a previous incomplete run of $THIS)
  -v: verbose mode
  -z: use compression when transferring files (-zz is used if rsync version >=3.1.1)

Details: Before $THIS can work, you must have added the root public key of \
source machine (/root/.ssh/id_rsa.pub) to destination machine in \
file /root/.ssh/authorized_keys.

If a prior instance of $THIS is already running, \
a new instance will abort unless called with -r.

If source /home is on a btrfs or LVM volume, $THIS will \
create and use a temporary snapshot of such volume for the operation - this can be \
overridden with -e option.

Mutual_Mirroring: Every Timedicer Server machine has a BaseID single digit which is normally 1. \
This default value is overridden based on the last character (digit) in file \
/opt/baseid or, if there is no such file, the last character (digit) of the \
machine's hostname. $THIS \
will only backup /home subdirectories that are homes for users with uids \
in the range (1000xBaseID)+1 to (1000xBaseID)+999 - normally 1001-1999 - \
these are considered the 'local TimeDicer users'.

Users created through the TimeDicer web interface will have uids and gids \
which conform to this specification, and it is required for mutual \
mirroring (bi-directional). If setting up more than one TimeDicer Server and \
you might one day want to perform mutual mirroring (where the second machine \
has its own local TimeDicer backups and runs $THIS back to the first as well \
as vice-versa), you \
are strongly advised to ensure that they have different BaseIDs e.g. by naming \
the first 'timedicer1' and the second 'timedicer2'.

Warning: Because of the major changes which it makes to the destination \
machine, you should not run $THIS to a machine which has any other purpose \
than being a TimeDicer Server, either just as a mirror for your source machine \
or with its own local TimeDicer users in which case it must be configured \
with a different BaseID to the source machine (see above). $THIS may alters \
users and groups on the destination machine as well as overwriting some /home \
subdirectories and /opt. You have been warned!

Dependencies: [m/g]awk bash coreutils diffutils grep \
net-tools(hostname) iputils(ping) openssh ps rsync sed util-linux [wakeonlan]

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
if [ -n "$CHANGELOG" ]; then
	# changelog
	[ -n "$HELP" ] && echo -e "Changelog:"
	echo "\
6.0425 [25 Apr 2016] - attempt to fix timeout error creating snapshot ('special device does not exist')
6.0424 [24 Apr 2016] - really fix fatal error (since 6.0422)
6.0423 [23 Apr 2016] - bugfix fatal error
6.0422 [22 Apr 2016] - add -b switch, only mirror data for local timedicer \
users based upon the source machine's BaseID
6.0115 [15 Jan 2016] - if rsync operation fails, check whether source \
snapshot has failed and abort if it has
5.1226 [26 Dec 2015] - bugfix copying of /etc/rdiffweb/rdw.db if destination \
directory doesn't exist
5.1210 [10 Dec 2015] - bugfix naming of LV (kudos bug report: Alex Racov)
5.1123 [23 Nov 2015] - increase timeout from 2 mins to 30 mins, use new \
rsync compression (-zz), use --append-verify (later removed)
5.0922 [22 Sep 2015] - fix bug identifying LV
5.0908 [08 Sep 2015] - updated help info
5.0813 [13 Aug 2015] - do not delete extraneous files from destination's /opt
5.0513 [13 May 2015] - minor improvement to LV identification
5.0331 [31 Mar 2015] - improved stop/restart code
5.0314 [14 Mar 2015] - speed optimisation (combined some remote ssh calls)
5.0313 [13 Mar 2015] - make compatible with btrfs and/or \
non-LVM-mapped filesystems, add -e (force-no-snapshot) option
5.0217 [17 Feb 2015] - minor tweaks
5.0130 [30 Jan 2015] - minor text changes and code tidying
5.0127 [27 Jan 2015] - minor text changes and bugfix
5.0123 [23 Jan 2015] - minor text changes and code tidying
5.0119 [19 Jan 2015] - move mac address to new -m option
5.0118 [18 Jan 2015] - fix bugs in file exclusions
5.0113 [13 Jan 2015] - code tidying
4.1230 [30 Dec 2014] - abort on error when obtaining destination backup space
4.1224 [24 Dec 2014] - remove compression if retrying after timeout \
(rsync bug 7757)
4.1220 [20 Dec 2014] - add -u option, change -n option to put destination to \
sleep, add 120s timeout to rsync, fix a bug where it failed to detect rsync \
failure in verbose or active progress modes
4.1211 [11 Dec 2014] - faster -f fast mode
4.1121 [21 Nov 2014] - add -i option and change -o option
4.0822 [22 Aug 2014] - improved/bugfixed comparing source and destination users
4.0814 [14 Aug 2014] - more bugfixes for large source and destination sizes
4.0813 [13 Aug 2014] - bugfixes for root LVM and large \
destination size, allow MAC addresses with dashes
4.0808 [08 Aug 2014] - test destination /var/lib/sudo/timedicer/0 is accessible
4.0730 [30 Jul 2014] - bugfix counting space used by destination /home/backup
4.0409 [09 Apr 2014] - resolve destination address explicitly (uses ping)
4.0324 [24 Mar 2014] - bugfix comparing users on source and destination
4.0123 [23 Jan 2014] - use specified SSH port for rsync too
4.0115 [15 Jan 2014] - re-open remote machine if powered off during -c checking
3.1011 [10 Oct 2013] - quit if any ongoing rdiff-backup verification processes
3.0918 [18 Sep 2013] - minor text changes
3.0916 [16 Sep 2013] - bugfix calculation of destination /home/backup space
3.0828 [28 Aug 2013] - test that destination /home is writeable
3.0803 [03 Aug 2013] - bugfix calculation of destination space
3.0530 [30 May 2013] - minor text changes
3.0523 [23 May 2013] - remove dg834g_src option
3.0514 [14 May 2013] - correct help text description of -o option
2.1117 [17 Nov 2012] - change option -o to check for enough space on \
destination instead of *not* checking (default behaviour is now *not* to check)
2.1107 [07 Nov 2012] - fix bug preventing creation of users and groups on \
destination
2.0929 [29 Sep 2012] - remove erroneous fail message on local ping
2.0821 [21 Aug 2012] - local ping test informational instead of critical, \
use /tmp instead of /var/tmp, deprecate dg834g_src, change previous -P \
(ssh port) switch to -p and previous -p switch ('live progress') to -a
2.0818 [18 Aug 2012] - add -k option to specify remote wakeonlan port
2.0721 [21 Jul 2012] - add -P option to specify remote SSH port, remove \
warnings about RSA host key not in list of known hosts
2.0715 [15 Jul 2012] - add -o option to skip remote machine space checking
2.0627 [27 Jun 2012] - fix for machine with hyphen in name and re-enable \
backup of /opt (n/w since 2.0317)
2.0607 [07 Jun 2012] - allow concurrent rdiff-backup verify/restore operations
2.0514 [14 May 2012] - improved help text
2.0412 [12 Apr 2012] - add code (for checksum mode) comparing usage of /home
2.0404 [04 Apr 2012] - further minor changes and bugfixes
2.0330 [30 Mar 2012] - bug fix for recording size of files
2.0325 [25 Mar 2012] - add recording of size of files \
transferred so that on subsequent runs the required space on destination \
can be better estimated
2.0317 [17 Mar 2012] - add explicit -z compression option, transfers no \
longer compressed by default
2.0313 [13 Mar 2012] - add -l 'changelog' option, change previous \
-l (i.e. 'live') option to be -p (i.e. 'progress')
2.0308 [08 Mar 2012] - renamed program from 'timedicer-mirror' to \
'timedicer-mirror.sh', improved help
1.1023 [23 Oct 2011] - exclude /home/tmp/*
1.1012a [12 Oct 2011] - copy .ssh and other hidden folders in user \
directories on fast copy (disabled in 4.1211)
1.1011 [11 Oct 2011] - further fixes and variable name changes
1.1010 [10 Oct 2011] - further fixes for base filesystem search
1.1009 [09 Oct 2011] - modify search for base filesystem
1.0818 [18 Aug 2011] - remove temporary files on successful completion
"|fold -s -w $COLUMNS
fi
[ -n "$CHANGELOG$HELP" ] && exit 0
# check we are running as root
[ "$(id -u)" != "0" ] && echo -e "Sorry, $THIS must be run as root\n">&2 && exit 1

STARTTIME=`date`
STARTDATETIME=`date +"%d/%m/%Y %H:%M:%S"`
MYIP="$(hostname -I|cut -d" " -f1)"
#MYIP=`ifconfig 2>/dev/null|sed -n '/inet addr:/{s/.*inet addr:\([^ ]*\).*/\1/;/127\.0\.0\.1/d;p;q}'`
valid_ipv4 "$MYIP" || { echo "Bad local ipv4: '$MYIP', aborting..." >&2; exit 1; }

#  Check if this script is already running
#    This looks for running processes with the same name as this, then filters out any:
#      - dead or defunct processes ('s' field is status - exclude X or Z)
#      - with the same pid $$ as this one
#      - with the same parent pid $PPID as this one
PRIOR="$(ps --no-headers -o "s,pid,ppid,sid,args" -ww -C "$THIS"|sed -n "/^[XZ] /d;/ $$ /d;/ $PPID /d;p")"
if [ ! -z "$PRIOR" ]; then
	if [ -n "$STOP" -o -n "$RESTART" ]; then
		#extract just the pids for each identified process
		[ -z "$QUIET" ] && echo -e "$THIS prior process(es):\n$PRIOR"
		PRIORPIDS=`echo -e "$PRIOR" | awk '{printf $2" "}'`
		[ -z "$QUIET" ] && echo "Terminating PID(s)   : $PRIORPIDS"
		kill -9 $PRIORPIDS
		[ -n "$STOP" ] && exit 0
		unset RESTART
	else
		[ -z "$QUIET" ] && echo -e "$THIS is already running:\n$PRIOR\n(Our PID,PPID: $$,$PPID)" >&2
		exit 1
	fi
fi

if [ -n "$STOP$RESTART" ]; then
	[ -z "$QUIET" ] && echo "$THIS was not running so was not stopped" >&2
	[ -n "$STOP" ] && exit 1
	unset RESTART
fi

# quit if rdiff-backup is running except for restore, list, compare (this will also block
# rdiff-backup operations running from remote machine i.e. --server)
if [ -z "$TEST$FAST" ]; then
	[ -n "`ps h -ww -C rdiff-backup|grep -E -v " (--restore|-r |--list|-l |--compare)"`" ] && echo "$THIS aborting - rdiff-backup is running">&2 && exit 1
fi

# obtain and validate destination ip
[ -z "$1" ] && { echo -e "dest_address not specified\nRoutine aborted...">&2; exit 1; }
DESTNAME="$1"
# note ping does not have to succeed, we just use it to decode DNS name to IPv4 address
DESTIP="$(ping -q -c1 -t1 $DESTNAME 2>/dev/null | sed -n "/PING/{s/^[^(]*[(]//;s/[)].*$//;p}")"
valid_ipv4 "$DESTIP" || { echo "Bad destination ipv4: '$DESTIP', aborting..." >&2; exit 1; }

# validate mac
if [ -n "$MACADDR" ]; then
	# convert mac address - acceptable input forms are 6x semicolon- or dash- separated or unseparated hex pairs
	# result is semicolon separated, upper or lower case
	BACKUP2MAC=`echo "$MACADDR"|sed -rn "s/^([0-9A-Fa-f]{2})[-:]?([0-9A-Fa-f]{2})[-:]?([0-9A-Fa-f]{2})[-:]?([0-9A-Fa-f]{2})[-:]?([0-9A-Fa-f]{2})[-:]?([0-9A-Fa-f]{2})$/\1:\2:\3:\4:\5:\6/p"`
	if [ -z "$BACKUP2MAC" ]; then
		echo -e "Bad destination mac address: '$MACADDR'\n$THIS aborted..." >&2
		exit 2
	fi
	#[ -n "$VERBOSE" ] && echo "Destination mac: $BACKUP2MAC"
fi

# establish the BASEID, default 1 (i.e. local userids are 1001-1999)
#   it can be defined as the last digit in /opt/baseid, or if hostname ends in a digit it uses that digit
[[ -s /opt/baseid ]] && BASEID=$(cat /opt/baseid) || BASEID=$(hostname)
BASEID=$(echo $BASEID|tail -n1|awk '{BASEID=substr($1,length($1)); if (BASEID+0>=1) {print BASEID} else {print 1}}')
# it should be impossible to get non-numeric BASEID but just in case...
[[ $BASEID -lt 1 || $BASEID -gt 9 ]] && { echo "Invalid BASEID '$BASEID', can't continue" >&2; exit 1; }


if [ -z "$QUIET" ]; then
	echo -e "Started:\t $STARTTIME"
	[ -n "$CHECKSUM" ] && echo -e "Checksum mode:\t Using rsync checksum for all files - will take longer!"
	if [ -n "$ACTIVE" ]; then
	echo -e "Active mode:\t Verbose output with file transfer progress"
	else
	[ -n "$VERBOSE" ] && echo -e "Verbose mode"
	fi
	[ -n "$DEBUG" ] && echo -e "Debug mode:\t undocumented, could give unpredictable results"
	[ -n "$TEST" ] && echo -e "Test mode:\t no changes on destination"
	[ -n "$USEEXISTINGSNAPSHOT" ] && echo -e "Use pre-existing snapshot"
	echo -en "Space checks:\t "
	if [ -n "$FAST" ]; then
		echo "no space checking on destination"
	elif [ -n "$NOSPACECHECKS" ]; then
		echo "check total but not available space on destination"
	elif [ -z "$IGNORESPACECHECK" ]; then
		echo "check total and available space on destination"
	else
		echo "check total and available space on destination - but ignore outcome"
	fi
	echo -e "BaseID $BASEID:\t local TimeDicer user uids ${BASEID}001-${BASEID}999"
	[[ -n $BIDIRECTIONAL ]] && echo -e "Bidirectional:\t continue if users on destination unmatched on source"
	[ -n "$NOSNAP" ] && echo -e "Force no snap:\t backup will be from live /home not a snapshot"
	[ -n "$COMPRESS" ] && echo -e "Compress:\t rsync compression turned on"
	[ -z "$NOSLEEP" ] && echo -e "Sleep mode:\t destination machine will be powered off at end"
	echo -e "Source:  \t $HOSTNAME ($MYIP)\nDestination:\t $DESTNAME ($DESTIP) port $SSHPORT (TCP)"
	[ -n "$BACKUP2MAC" ] && echo -e "Destination WOL: $BACKUP2MAC port $WAKEPORT (UDP)"
	echo -en "${MODIFIERTC}Mirroring:\t /opt"
	[ -f "/etc/rdiffweb/rdw.db" ] && echo -n " /etc/rdiffweb/rdw.db"
	[ -z "$FAST" ] && echo -n " /home (local TimeDicer users only)"
	echo; echo
fi

# suspend any verification processes that are ongoing
#VERIFYPROCESSES=$(ps -f -C rdiff-backup|grep "verify"|awk '{printf $2" "}'
#if [ -n "$VERIFYPROCESSES" ]; then
#	kill -STOP $VERIFYPROCESSES
#	[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Suspended rdiff-backup verification processes $VERIFYPROCESSES"
#fi

# flag warning if can't ping self
ping -q -c 2 $MYIP >/dev/null || echo "Warning: Unable to ping source ip address ($MYIP), does this computer have a valid network connection?"

#get space *used* on source FS in K
DFLOCAL=`df -PT /home 2>/dev/null|tail -n 1`
LOCALMNT=`echo "$DFLOCAL"|awk '{printf $7}'`
LOCALMNT=${LOCALMNT:1}	# remote initial slash to give e.g. "home" or ""
[ -z "$LOCALMNT" ] && LOCALMNT="root"
[ "$LOCALMNT" != "home" -a "$LOCALMNT" != "root" ] && { echo "`date +%H:%M:%S`  Invalid source mount point '$LOCALMNT', aborting..." >&2; exit 1; }
LOCALFS=`echo "$DFLOCAL"|awk '{print $2}'` # e.g. or "btrfs" or "ext4"
LOCALSPACEUSED=`echo "$DFLOCAL"|awk '{printf ("%.0f", $4)}'`
if [ -n "$NOSNAP" ]; then
	SNAPTYPE="none"
elif [ "$LOCALFS" = "btrfs" ]; then
	SNAPTYPE="btrfs"
else
	vgs --version >/dev/null 2>&1
	if [ $? -gt 0 ]; then
		SNAPTYPE="none"
	else
		# this is ugly, but needed to change e.g. /dev/mapper/timedicer1-root to /dev/timedicer1/root
		LOCALDEVICE="`echo "$DFLOCAL"|awk '{print $1}'|sed 's@/mapper@@;s@--@!!@g;s@-@/@g;s@!!@-@g'`"
		# check that the device holding /home is indeed an LV
		if [ -z "$(lvs --noheadings -o lv_path|grep "^  $LOCALDEVICE *$")" ]; then
			SNAPTYPE="none"
			echo "`date +%H:%M:%S` $LOCALDEVICE is not a logical volume, will not use snapshot"
		else
			SNAPTYPE="lvm"
		fi
	fi
fi
[ -z "$LOCALSPACEUSED" ] && { echo "Unable to obtain used space on source filesystem '$LOCALMNT', aborting...">&2; quit 1; }
[ -n "$DEBUG" ] && echo -e "LOCALMNT: '$LOCALMNT'\nLOCALDEVICE: '$LOCALDEVICE'\nSNAPTYPE: '$SNAPTYPE'\nLOCALSPACEUSED: '$LOCALSPACEUSED'"

test_and_wake_dest || quit $?

[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Checking destination /home is writeable "
# REMOTEDATA returns 9 fields e.g. /dev/mapper/timedicer-home btrfs   440401920 346466188  92802080      79% /home 1 600
# where the fields 0-6 are the 2nd (i.e. data) line df -PT /home output, field 7 is 1 if /home is writeable (0 if not), field 8 is 600 if /var/lib/sudo/timedicer/0 is writeable
REMOTEDATA=( $(ssh $SSHOPTS root@$DESTIP 'mount >/tmp/mount.txt; df -PT /home|tail -n1 >/tmp/out1.txt; grep -c "$(cut -f1 -d" " /tmp/out1.txt).*(rw" /tmp/mount.txt >>/tmp/out1.txt; cat /tmp/out1.txt; find /var/lib/sudo -name 0 -execdir stat -c %a {} + ;[ -d /etc/rdiffweb ] && echo y || echo n; rm /tmp/mount.txt /tmp/out1.txt') ) || { echo "Unable to check destination /home status, aborting...">&2; quit 1; }
if [ "${REMOTEDATA[7]}" != "1" -o ${#REMOTEDATA[@]} -ne 10 ]; then
	[ -z "$QUIET" ] && echo "- FAIL"
	echo "`date +%H:%M:%S` read-only, aborting...">&2
	puttosleep
	[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` " >&2
	echo "Aborting...">&2
	quit 2
elif [ -z "$QUIET" ]; then
	echo "- ok"
fi
[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Checking destination /var/lib/sudo/.../0 is writeable "
# check that base system is in a normal state on destination
if [ "${REMOTEDATA[8]}" != "600" ]; then
	[ -z "$QUIET" ] && echo "- FAIL"
	echo "`date +%H:%M:%S` read-only, aborting...">&2
	puttosleep
	[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` " >&2
	echo "Aborting...">&2
	quit 2
elif [ -z "$QUIET" ]; then
	echo "- ok"
fi

# get space *available* (used and unused) on remote FS in K
[ -n "$DEBUG" ] && echo "Debug mode: stage 3"
if [ -z "$FAST" ]; then # line XXX - see matching fi below
[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Checking destination /home total disk space "
REMOTEFS="${REMOTEDATA[1]}"
REMOTESPACETOTAL="${REMOTEDATA[2]}"
if [ -z "$REMOTESPACETOTAL" -o "$REMOTESPACETOTAL" = "0" ]; then
	echo "Unable to obtain used space on destination filesystem, aborting...">&2
	quit 1
fi
[ -z "$QUIET" ] && echo -n "- $(($REMOTESPACETOTAL/1024**2))G"
# skip further space checking?
if [ -n "$NOSPACECHECKS" ]; then
	[ -z "$QUIET" ] && echo " - skipping checks on available space"
else
[ -z "$QUIET" ] && echo -en "\n`date +%H:%M:%S` Checking destination /home/backup space used "
# get space on remote FS /home/backup, excluding hard links
# thanks to StephaneChazelas http://unix.stackexchange.com/questions/52876/how-to-du-only-the-space-used-up-by-files-that-are-not-hardlinked-elsewhere
REMOTEHOMEBACKUP=`ssh $SSHOPTS root@$DESTIP 'find /home/backup -links -2 -print0 2>&-|du -kc --files0-from=- 2>&-|tail -n 1|cut -f1'` || { echo "Unable to obtain used /home/backup space on destination, aborting...">&2; quit 1; }
[ -n "$DEBUG" ] && echo "REMOTEHOMEBACKUP: '$REMOTEHOMEBACKUP'"
[ -z "$REMOTEHOMEBACKUP" ] && REMOTEHOMEBACKUP=0
[ -z "$QUIET" ] && echo "- $(($REMOTEHOMEBACKUP/1024**2))G"

REMOTESPACEAVAILABLE=`echo "${REMOTEDATA[4]} $REMOTEHOMEBACKUP"|awk '{printf ("%.0f", $1+$2)}'`
[ -n "$DEBUG" ] && echo "Debug mode: stage 5"
SHORTAGE=$(( $LOCALSPACEUSED - $REMOTESPACETOTAL ))
if [ $? -ne 0 ]; then
	echo "An error occurred calculating space, aborting...">&2
	quit 1
fi
# delete any previous temporary files
[ -z "$DEBUG" ] && rm -f /tmp/backup2_*

# analyse usage of /home on source and dest - slow!
# du is too slow with btrfs so skip it in this case
DIFFHOMESIZE=0
if [ -n "$CHECKSUM" -a "$LOCALFS" != "btrfs" -a "$REMOTEFS" != "btrfs" ]; then
	if [ -z "$DEBUG" -o ! -f "/tmp/backup2_home_dest" -o ! -f "/tmp/backup2_home_source" ]; then
		[ -z "$QUIET" ] && echo -e "`date +%H:%M:%S` Obtaining usage of /home on source & destination"
		ssh $SSHOPTS "root@$DESTIP du /home/* -xms --exclude=/home/backup" >/tmp/backup2_home_dest 2>/dev/null &
		REMOTEDUID=$!
		du /home/* -xms --exclude="/home/backup" >/tmp/backup2_home_source 2>/dev/null
		# wait until the destination information is ready
		WAITCOUNT=0
		while [ -n "`ps -p $REMOTEDUID --no-headers`" ]; do
			if [ $WAITCOUNT -gt 60 ]; then
				echo -e "\nUnable to obtain /home analysis of destination, aborting...">&2
				quit 1
			elif [ $WAITCOUNT -eq 0 -a -z "$QUIET" ]; then
				echo -en "`date +%H:%M:%S` Waiting for usage of /home on destination"
			fi
			sleep 1m
			[ -z "$QUIET" ] && echo -n "."
			let WAITCOUNT++
		done
		# if the remote analysis finished earlier then the remote machine may have switched off in the
		# meantime, so check for this and put it back on if so
		[ $WAITCOUNT -eq 0 ] && { test_and_wake_dest || quit $?; }
	fi
	[ -z "$QUIET" ] && echo -e "`date +%H:%M:%S` Analysing usage of /home on source and destination"
	while read SOURCEAMT SOURCELOC; do
		SOURCELOCESC="${SOURCELOC//\//\\/}"
		DESTAMT="`sed -n "/\s${SOURCELOCESC}$/s/\s.*//p" /tmp/backup2_home_dest`"
		[ -z "$DESTAMT" ] && DESTAMT=0
		[ $(($DESTAMT*100)) -gt $(($SOURCEAMT*105)) ] && echo "Warning: $SOURCELOC is bigger on destination (${DESTAMT}M) than on source (${SOURCEAMT}M)!"
		[ $DESTAMT -gt $SOURCEAMT ] && DESTAMT="$SOURCEAMT"
		# DIFFHOMESIZE is cumulative additional space used on /home/* on source over dest
		DIFFHOMESIZE="$(($DIFFHOMESIZE+$SOURCEAMT-$DESTAMT))"
		[ -n "$DEBUG" ] && echo "$SOURCELOC: source ${SOURCEAMT}M vs dest ${DESTAMT}M, DIFFHOMESIZE +$(($SOURCEAMT-$DESTAMT))M"
	done</tmp/backup2_home_source
	[ -n "$DEBUG" ] && echo "DIFFHOMESIZE: ${DIFFHOMESIZE}"
	if [ $DIFFHOMESIZE -gt 3096 ];then
		DIFFHOMESIZETEXT="$(($DIFFHOMESIZE/1024))G"
	else
		DIFFHOMESIZETEXT="${DIFFHOMESIZE}M"
	fi
	[ -z "$QUIET" ] && echo -e "`date +%H:%M:%S` $DIFFHOMESIZETEXT more used on source /home/* than on destination"
	sed -i '/to Ubuntu/d;/Documentation:/d;/information as of/d;/load:/d;/Users logged in/d;/usage:/d;/this data and manage/d' /tmp/backup2_home_dest
	while read DESTAMT DESTLOC; do
		if [ -z "`grep "$DESTLOC$" /tmp/backup2_home_source`" ]; then
			echo "Warning: '$DESTLOC' exists only on destination!"
		fi
	done</tmp/backup2_home_dest
fi
[ -n "$DEBUG" ] && echo "Debug mode: stage 7"

if [ -z "$FAST" ]; then
	if [ -z "$QUIET" ]; then
		echo -en "`date +%H:%M:%S` $(($LOCALSPACEUSED/1048576))G used on source /home, $(($REMOTESPACETOTAL/1048576))G total (incl unused) on destination /home"
		if [ $SHORTAGE -gt 0 ]; then
			echo " - $(($SHORTAGE/1048576))G implicit shortage"
		else
			echo " - $(((0-$SHORTAGE)/1048576))G implicit surplus - ok"
		fi
		echo -en "`date +%H:%M:%S` $(($REMOTESPACEAVAILABLE/1048576))G available on destination"
	fi
	# default headroom is 10G
	HEADROOM=10485760
	if [ -e "/var/log/$THIS-tfs.log" ]; then
		# pick up largest previous files transferred size in last 30 runs and add 5GB (represented in K)
		TFS="`tail -n 30 "/var/log/$THIS-tfs.log"|sort -rn|awk '{if (NR==1) {printf "%d",($1/1024+5*1048576)}}'`"
		[ -n "$DEBUG" ] && echo -en "\nTFS: ${TFS}K"
		if [ $TFS -gt $HEADROOM ]; then HEADROOM=$TFS; fi
		[ -n "$DEBUG" ] && echo -n ", HEADROOM: ${HEADROOM}K"
		TYPEOFHEADROOM="est headroom needed (based on last 30 runs, adding 5G)"
	elif [ -z "$QUIET" ]; then
		TYPEOFHEADROOM="default headroom needed"
	fi
	[ -z "$QUIET" ] && echo -en ", $(($HEADROOM/1048576))G ${TYPEOFHEADROOM}"
	# check if we have enough headroom on destination machine
	if [ -z "$IGNORESPACECHECK" ] && [ $SHORTAGE -gt -$HEADROOM -o $REMOTESPACEAVAILABLE -lt $HEADROOM ]; then
		echo >&2
		[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` " >&2
		echo -en "Insufficient space on destination $DESTIP: " >&2
		if [ $SHORTAGE -gt -$HEADROOM ]; then
			echo -e "$(($SHORTAGE/1048576))G shortage vs.$(($HEADROOM/1048576))G headroom" >&2
		else
			echo -e "$(($REMOTESPACEAVAILABLE/1048576))G space available vs.$(($HEADROOM/1048576))G headroom" >&2
		fi
		[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` " >&2
		echo -e "Unable to continue - please add some storage to destination">&2
		puttosleep
		[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` " >&2
		echo "Aborting...">&2
		quit 3
	elif [ -z "$QUIET" ]; then
		if [ -n "$IGNORESPACECHECK" ]; then
			[ -z "$QUIET" ] && echo " - ignoring space check"
		else
			echo " - ok"
		fi
	fi
fi
fi # matches with 'if [ -n "$NOSPACECHECKS" ]; then' above
fi # matches with 'if [ -z "$FAST" ]; then # line XXX - see matching fi below' above

[ -n "$DEBUG" ] && echo "Debug mode: stage 12"

# Now check for users on destination and compare with source
# any that are missing on destination are created there, with same group and
# same uid and same gid as on source
[ -z "$QUIET" ] && echo -e "`date +%H:%M:%S` Comparing source and destination users/groups"

#identify primary user's home here - normally will just be the primary user's name preceded by slash
PRIMARYUSER_HOME=`grep 1000 /etc/passwd|awk -F : '{print $6}'|sed 's@^/home@@'`
#identify users here
awk -F: '($3>=1001) && ($3!=65534) {print $1 ":" $3 ":" $4}' /etc/passwd|sort -t: -k2 >/tmp/backup2_users1.txt
#identify users on BACKUP2
rm -f /tmp/backup2_err.txt /tmp/backup2_users2.txt
[ -n "$DEBUG" ] && echo "Debug mode: stage 14"
ssh $SSHOPTS root@$DESTIP cat /etc/passwd 2>/dev/null | awk -F: '($3>=1001) && ($3!=65534) {print $1 ":" $3 ":" $4}'|sort -t: -k2 >/tmp/backup2_users2.txt 2>/tmp/backup2_err.txt
[ -n "$DEBUG" ] && echo "Debug mode: stage 15"

if [ -s /tmp/backup2_err.txt -o ! -f /tmp/backup2_users2.txt ]; then
	echo "An error occurred obtaining user data from destination:">&2
	cat /tmp/backup2_err.txt>&2
	quit 2
fi

# show any users on destination whose name/id is not matched on source
for PREEXISTINGUSER in $(diff --suppress-common-lines /tmp/backup2_users1.txt /tmp/backup2_users2.txt|awk '($1==">") && ($2!="") {print $2}'); do
	if [[ -z $BIDIRECTIONAL ]]; then
		let ERRED++
		echo "Fatal Error: user $PREEXISTINGUSER exists on destination and is not matched on source" >&2
	else
		echo "Note: user $PREEXISTINGUSER exists on destination and is not matched on source"
	fi
done
[ -z "$ERRED" ] || { echo "Aborting..."; puttosleep; quit 1; }

#create list of users found here but missing on BACKUP2
diff --suppress-common-lines /tmp/backup2_users1.txt /tmp/backup2_users2.txt|awk '($1=="<") && ($2!="") {print $2}'>/tmp/backup2_usersnew.txt
if [ -s /tmp/backup2_usersnew.txt ]; then
	# check that none of these new users already exist on dest with different uid/gid
	cut -f1 -d: /tmp/backup2_usersnew.txt|xargs -I{} grep "^{}:" /tmp/backup2_users2.txt >/tmp/backup2_userswrongid.txt
	if [ -s /tmp/backup2_userswrongid.txt ]; then
		if [[ -n $TEST ]]; then
			echo "Warning: user(s) on destination with same name but different userid and/or groupid to source:"
			cat /tmp/backup2_userswrongid.txt
			echo " - continuing because we are in test mode"
		else
			echo "Fatal Error: user(s) on destination with same name but different userid and/or groupid to source:" >&2
			cat /tmp/backup2_userswrongid.txt >&2
			puttosleep; echo "Aborting..." >&2; quit 1
		fi
	fi
	if [ -z "$QUIET" ]; then
		echo Users to be added to destination:
		cat /tmp/backup2_usersnew.txt
	fi
else
	if [ -z "$QUIET" ]; then
		echo `date +%H:%M:%S` No users need to be added to destination
	fi
fi
[ -n "$DEBUG" ] && echo "Debug mode: stage 18"
#add any missing users from here to BACKUP2
for LINE in $(cat /tmp/backup2_usersnew.txt); do
	#split each line into username uid and gid
	echo $LINE | (
		IFS=:
		while read USERNAME USERID GROUPID; do
			unset IFS
			GROUPNAME=`awk -F: -v gid=$GROUPID '($3==gid) {printf $1}' /etc/group`
			if [ -n "$TEST" ]; then
				echo "Test mode: not added - username:$USERNAME,uid:$USERID,gid:$GROUPID,groupname:$GROUPNAME"
			else
				[ -n "$VERBOSE" ] && echo "Adding to destination: group $GROUPNAME with gid $GROUPID for username $USERNAME uid $USERID"
				[ -n "$DEBUG" ] && echo "Doing: ssh $SSHOPTS root@$DESTIP addgroup --gid $GROUPID $GROUPNAME"
				ssh $SSHOPTS root@$DESTIP addgroup --gid $GROUPID $GROUPNAME
				ADDGROUPERR=$?
				if [ $ADDGROUPERR != 0 ]; then
					echo -e "Unable to add group '$GROUPNAME' gid $GROUPID, error $ADDGROUPERR\nSkipping the attempt to add username '$USERNAME' uid $USERID..."
				else
					[ -n "$VERBOSE" ] && echo "Adding to destination: user '$USERNAME' with uid $USERID"
					ssh $SSHOPTS root@$DESTIP adduser --uid $USERID --gid $GROUPID --disabled-password --gecos "$USERNAME" "$USERNAME"
					if [ $? != 0 ]; then
						echo Unable to add user '$USERNAME' uid $USERID, error $?
					else
						echo User $USERNAME uid $USERID Group $GROUPNAME gid $GROUPID added
					fi
				fi
			fi
			IFS=:
		done
		unset IFS
		)
done
#test for and maybe delete any surplus users on BACKUP2? ...not implemented
[ -n "$DEBUG" ] && echo "Debug mode: stage 22"

# make/update copies of source crontab and rc.local in source /opt
for FILE in /etc/crontab /etc/rc.local; do
	if [ -f "$FILE" -a -z "$TEST" ]; then
		[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Copying $FILE to /opt on source"
		cp -a "$FILE" /opt
	fi
done
#copy /opt/ and rdw.db (no LVM snapshot as these will be quick anyway)
if [[ ${REMOTEDATA[9]} == "y" ]]; then
	SOURCES="/opt/ /etc/rdiffweb/rdw.db"
else
	SOURCES="/opt/"
	echo -e "Warning: /etc/rdiffweb directory not found on destination\n         /etc/rdiffweb/rdw.db will not be copied!"
fi
for SRC in $SOURCES; do
	if [ -e "$SRC" ]; then
		[ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` Mirroring $SRC"
		if [ -n "$TEST" ]; then
			echo " - skipped [test mode]"
		else
			rsync --rsh="ssh -p$SSHPORT" --exclude /baseid $RSYNCADDOPTIONS "$SRC" "root@$DESTIP:${SRC%/*}" 1>/tmp/backup2_rsync.txt 2>&1
			if [ "$?" -gt 0 ]; then
				echo -e "\n  There was a problem running rsync for $SRC:"
				sed 's/^/  /' /tmp/backup2_rsync.txt
				[ -z "$QUIET" ] && echo
			elif [ -z "$QUIET" ]; then
				echo " - ok"
			fi
		fi
	else
		echo "`date +%H:%M:%S` Mirroring $SRC - skipped [not found on source]"
	fi
done

if [ -n "$FAST" ]; then	# XXY: matches fi below
	RSYNCERR=0
else

# implement re-gzipping of newly-gzipped files so that they are rsyncable
# ... but not needed because rdiff-backup's gz files are never changed once created
#if [[ -s /var/log/$THIS.log ]]; then
#	# pick up the time (formatted as required for touch) for the last successful run to this destination
#	LASTSUCCESS=$(tac /var/log/$THIS.log|grep ",${DESTIP}$"|awk -F, '{print $2}')
#	if [[ -n $LASTSUCCESS ]]; then
#		touch -t $LASTSUCCESS /tmp/backup2_timematch.tmp
#		echo "Listing gz files modified since the last time $THIS was run to $DESTIP:"
#		find /home -type f -name "*.gz" -newer /tmp/backup2_timematch.tmp -ls
#	fi
#fi

[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Preparing destination /home/backup"
# plant $QUIET var so it can be accessed on remote machine (quotes not apostrophes so variable can be passed)
# run remote code to create remote /home/backup and report if already present and non-empty
ssh $SSHOPTS root@$DESTIP "echo $QUIET>/tmp/backup2_quiet;"'read QUIET</tmp/backup2_quiet
 ERRNO=$?
 mkdir -p /home/backup|| let ERRNO++
 [ -z "$QUIET`find /home/backup -maxdepth 0 -empty`" ] && echo "`date +%H:%M:%S` Note: existing non-empty destination /home/backup (probably the previous run failed)"
 exit $ERRNO
' 2>/dev/null
ERRNO=$?
# if an error has been recorded on the remote machine, or ssh failed, abort
if [ $ERRNO -ne 0 ]; then
 [ -n "$DEBUG" ] && echo -e " ERRNO is '$ERRNO'"
 echo -e "`date +%H:%M:%S` Fatal error preparing destination $DESTIP:/home/backup, aborting...">&2
 puttosleep
 quit 1
fi

# Set up the source (snapshot)
case $SNAPTYPE in
lvm)
	if [ `echo $LOCALDEVICE|awk -F/ '{print NF}'` != 4 ]; then
		# lv should be in the form /dev/xx/$LOCALMNT
		echo -e "`date +%H:%M:%S` couldn't identify '$LOCALMNT' volume name (found '$LOCALDEVICE')\nLV Name line is: '`lvdisplay 2>/dev/null|grep "^  LV Name.*$LOCALMNT$"`'\naborting...">&2
		puttosleep
		quit 1
	fi
	# remove any pre-existing mount ${LOCALDEVICE}backup
	if [ -n "`cat /etc/mtab|grep /mnt/${LOCALMNT}backup`" -a -z "$USEEXISTINGSNAPSHOT" ]; then
		if [ -z "$QUIET" ]; then echo "`date +%H:%M:%S` Removing existing source mount /mnt/${LOCALMNT}backup"; fi
		umount ${LOCALDEVICE}backup
		if [ $? -gt 0 ]; then
			umount -l ${LOCALDEVICE}backup||{ echo -e "\n`date +%H:%M:%S` Unable to umount pre-existing ${LOCALDEVICE}backup, aborting...">&2; [ -z "$TEST" ] && puttosleep; quit 1; }
			sleep 5
		fi
	fi
	# remove any pre-existing snapshot ${LOCALDEVICE}backup
	COUNTEXISTINGSNAPSHOTS=`lvs --noheadings ${LOCALDEVICE}backup 2>/dev/null|wc -l`
	if [ $COUNTEXISTINGSNAPSHOTS -gt 0 -a -z "$USEEXISTINGSNAPSHOT" ]; then
		[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Removing existing source LV ${LOCALDEVICE}backup"
		for ((LVREMOVELOOP=1; LVREMOVELOOP<11; LVREMOVELOOP++)); do
			[ $LVREMOVELOOP -gt 1 ] && sleep 30
			lvremove -f ${LOCALDEVICE}backup >/dev/null && break
			dmsetup remove -f ${LOCALDEVICE}backup >/dev/null || lvchange -an ${LOCALDEVICE}backup >/dev/null
			[ -z "$QUIET" ] && echo -n "."
		done
		if [ $LVREMOVELOOP -eq 11 ]; then
			[ -z "$QUIET" ] && echo " - failed"
			echo " `date +%H:%M:%S` Unable to remove LV ${LOCALDEVICE}backup. Aborting" >&2
			puttosleep
			quit 1
		fi
		[ -z "$QUIET" ] && echo " - ok"
	elif [ -n "$USEEXISTINGSNAPSHOT" ]; then
		if [ $COUNTEXISTINGSNAPSHOTS -gt 0  ]; then
			if [ -z "$(df /mnt/${LOCALMNT}backup|awk '{if (NR==2) print $1}')" ]; then
				echo "`date +%H:%M:%S` Data not found at /mnt/${LOCALMNT}backup. Aborting" >&2
				puttosleep
				quit 1
			fi
			echo "`date +%H:%M:%S` Using existing source LV ${LOCALDEVICE}backup"
		else
			echo "`date +%H:%M:%S` Unable to locate existing source LV ${LOCALDEVICE}backup. Aborting" >&2
			puttosleep
			quit 1
		fi
	fi
	if [ -z "$USEEXISTINGSNAPSHOT" ]; then
		[ -z "$QUIET" ] && echo -n "`date +%H:%M:%S` Making LVM snapshot of source $LOCALDEVICE at ${LOCALDEVICE}backup"
		[[ -n $DEBUG ]] && echo -e "\nDoing: lvcreate -p r -L 4G -s -n ${LOCALDEVICE##*/}backup $LOCALDEVICE"
		lvcreate -p r -L 4G -s -n ${LOCALDEVICE##*/}backup $LOCALDEVICE>/dev/null||{ echo -e "\ncouldn't create logical volume ${LOCALDEVICE}backup, aborting...">&2; puttosleep; quit 1; }
		[ -z "$QUIET" ] && echo -en " - ok\n`date +%H:%M:%S` Mounting source LVM snapshot at /mnt/${LOCALMNT}backup"
		for ((LOOP=1; LOOP<15; LOOP++)); do
			mkdir -p /mnt/${LOCALMNT}backup 2>/dev/null && break
			[[ -z $QUIET ]] && echo -n "."
			sleep 3s # wait for snapshot to exist, might loop to prevent error 'special device ... does not exist' when mounting
		done
		[[ $LOOP -lt 15 ]] || { echo -e "\ncouldn't create mountpoint, aborting...">&2; puttosleep; quit 1; }
		[[ -n $DEBUG ]] && echo -e "\nDoing: mount -o ro ${LOCALDEVICE}backup /mnt/${LOCALMNT}backup"
		mount -o ro ${LOCALDEVICE}backup /mnt/${LOCALMNT}backup||{ echo -e "\ncouldn't mount ${LOCALDEVICE}backup at mountpoint, aborting...">&2; puttosleep; quit 1; }
		[ -z "$QUIET" ] && echo " - ok"
	fi
	if [ "$LOCALMNT" = "home" ]; then
		BACKUPFROM=/mnt/homebackup
	else
		BACKUPFROM=/mnt/${LOCALMNT}backup/home
	fi
	;;
btrfs)
	BACKUPFROM=/$LOCALMNT/timedicer-mirror-snapshot
	# check for existence of snapshot
	btrfs subvolume show $BACKUPFROM >/dev/null 2>&1; SNAPSHOTEXISTS=$?
	if [ -n "$USEEXISTINGSNAPSHOT" ]; then
		if [ $SNAPSHOTEXISTS -eq 0 ]; then
			echo "`date +%H:%M:%S` Unable to locate existing $SNAPTYPE snapshot $BACKUPFROM, aborting" >&2
			puttosleep
			quit 1
		fi
	else
		if [  $SNAPSHOTEXISTS -eq 0 ]; then
			[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Deleting existing $SNAPTYPE snapshot $BACKUPFROM"
			btrfs subvolume delete "$BACKUPFROM" >/dev/null || { echo "`date +%H:%M:%S`  Unable to remove $SNAPTYPE snapshot $BACKUPFROM, aborting" >&2; puttosleep; quit 1; }
		fi
		[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Creating readonly $SNAPTYPE snapshot of '/$LOCALMNT' in '$BACKUPFROM'"
		btrfs subvolume snapshot -r /$LOCALMNT "$BACKUPFROM" >/dev/null || { echo "`date +%H:%M:%S`  Unable to create $SNAPTYPE snapshot $BACKUPFROM, aborting" >&2; puttosleep; quit 1; }
	fi
	[ $LOCALMNT = "root" ] && BACKUPFROM=$BACKUPFROM/home
	;;
none)
	BACKUPFROM=/home
	if [ "$LOCALFS" = "btrfs" -a "$LOCALMNT" = "home" ]; then
		# we must exclude any subvolumes - untested @ 3 Mar 2015
		RSYNCADDOPTIONS="$RSYNCADDOPTIONS $(btrfs subvolume list $LOCALMNT|awk '{printf "--exclude \"/"; for (F=9; F<NF; F++) printf $F" ";printf $NF"\" "}')"
	fi
	;;
esac

# do the main backup to hard-linked copy of /home/[folder] i.e. /home/backup/[folder]
# - that way if it fails part way then no harm is done

# list of exclusions for /home subfolders that are not homes for local TimeDicer users (BASEID is normally 1)
find /home -maxdepth 1 -mindepth 1 -type d|xargs -I {} awk -v BASEID=$BASEID -v HOMEF="{}" -F: '( ($6==HOMEF) && ($3!=1000) && ($3>=BASEID*1000) && ($3<(BASEID+1)*1000) ) {FOUND=1} END {if (FOUND!=1) print "- " HOMEF "/"}' /etc/passwd|sed "s@^- /home/@- /@g" >/tmp/backup2_$$_rsyncexcl.txt
[[ -n $DEBUG ]] && echo "exclude list:" && cat /tmp/backup2_$$_rsyncexcl.txt
for (( RSYNCLOOP=1; RSYNCLOOP<10; RSYNCLOOP++ )) do
  # in case the dest machine has gone to sleep...
  if [ $RSYNCLOOP -gt 1 ]; then
    test_and_wake_dest || { RSYNCLOOP=10; break; }
  fi
  [ -z "$QUIET" ] && echo -en "`date +%H:%M:%S` Start mirroring source /home (i.e. $BACKUPFROM)\n         to destination /home (i.e. /home/backup) - loop $RSYNCLOOP"
  RSYNCERR=99
  if [ -n "$TEST" ]; then
    RSYNCERR=0
		[[ -n $DEBUG ]] && echo "Test mode: rsync --dry-run --rsh=\"ssh -p$SSHPORT\" $RSYNCADDOPTIONS --delete-after --link-dest=/home --exclude-from=/tmp/backup2_$$_rsyncexcl.txt -vv --info=skip4 $BACKUPFROM/ root@$DESTIP:/home/backup" && rsync --dry-run --rsh="ssh -p$SSHPORT" $RSYNCADDOPTIONS --delete-after --link-dest=/home --exclude-from=/tmp/backup2_$$_rsyncexcl.txt -vv --info=skip4 $BACKUPFROM/ root@$DESTIP:/home/backup 2>&1|tee "/tmp/backup2_rsync.txt"
  elif [ -z "$VERBOSE" ]; then
    # AX options removed 7Oct10 because of rsync error messages:
    #   rsync: get_acl: sys_acl_get_file("path/filename", ACL_TYPE_ACCESS): No such file or directory (2)
    #   rsync: get_xattr_names: llistxattr("path/filename",1024) failed: No such file or directory (2)
    # backs up to /home/backup using --link-dest=/home

		# don't use --delete-during because it may make changes to dest before completion of backup operation,
		# whereas we want to delay any changes (using --link-dest) until backup has completed successfully
		# however this requires us to use --delete-after which is slower...
    rsync --rsh="ssh -p$SSHPORT" $RSYNCADDOPTIONS --delete-after --link-dest=/home --exclude-from=/tmp/backup2_$$_rsyncexcl.txt $BACKUPFROM/ root@$DESTIP:/home/backup 1>"/tmp/backup2_rsync.txt" 2>&1
    RSYNCERR=$?
  else	# verbose or active
    echo -e "\nStarted transfer,File length bytes,Transferred bytes,Path and filename"
    #the commented-out version provides neat formatting but you don't see the progress bar until 100% complete
    #(which is kinda self-defeating)
    #rsync --partial -AX $RSYNCADDOPTIONS --link-dest=/home --exclude=lost+found/*** --exclude=backup/*** --exclude=backup.old/*** /mnt/${LOCALMNT}backup/ root@$DESTIP:/home/backup 2>>/tmp/backup2_rsync.txt|sed 's/^[0-9/]*/ /;s/:/ /'
    #this is less neat but gives progress bar:
    rsync --rsh="ssh -p$SSHPORT" $RSYNCADDOPTIONS --delete-after --link-dest=/home --exclude-from=/tmp/backup2_$$_rsyncexcl.txt $BACKUPFROM/ root@$DESTIP:/home/backup 2>&1|tee "/tmp/backup2_rsync.txt"
    RSYNCERR="${PIPESTATUS[0]}"
  fi
  [ $RSYNCERR -eq 0 -o $RSYNCLOOP -gt 9 ] && break
  echo " - problem $RSYNCERR:"; sed '/known hosts\./d;s/^/   /' "/tmp/backup2_rsync.txt"
	if [[ $SNAPTYPE == "lvm" ]]; then
		lvs $BACKUPFROM >/dev/null 2>&1 || { echo "`date +%H:%M:%S` Source snapshot collapsed"; RSYNCLOOP=10; break; }
	fi
  if [ $RSYNCERR -eq 30 -a -n "$COMPRESS" ]; then
    RSYNCADDOPTIONS="$(echo "$RSYNCADDOPTIONS"|sed 's/-z //')"
    unset COMPRESS
    echo "`date +%H:%M:%S` Retrying without compression"
    [ -n "$DEBUG" ] && echo "RSYNCADDOPTIONS: '$RSYNCADDOPTIONS'"
	elif [ $(grep -c "No space left on device .28." /tmp/backup2_rsync.txt) -gt 0 ]; then
    echo "`date +%H:%M:%S` Out of space on destination"
		RSYNCLOOP=10; break
  else
    sleep 60s # if there was a problem with rsync, wait before trying again
  fi
done
[ -n "$DEBUG" ] && echo "Debug mode: stage 77"
[ -n "$TEST" ] && echo "       Test mode: /home mirroring did not really happen!">"/tmp/backup2_rsync.txt"
[ -n "$DEBUG" ] && echo "Debug mode: stage 79"
if [ -z "$QUIET" ] && [ -n "$TEST" -o -z "$VERBOSE" ]; then
  [ $RSYNCLOOP -lt 10 ] && echo " - ok:" || echo " - failed:"
  [ -n "$DEBUG" ] && echo "Debug mode: stage 80"
  # show tidied-up rsync output
  [ -s "/tmp/backup2_rsync.txt" ] && sed '/^$/d;/known hosts\./d;s/^/  /' "/tmp/backup2_rsync.txt"
fi
[ -n "$DEBUG" ] && echo "Debug mode: stage 81"
if [ -z "$TEST" ]; then
  TRANSFERRED_FILE_SIZE=`sed -n '/Total transferred file size/s/.*: \(.*\) .*/\1/p' "/tmp/backup2_rsync.txt"`
  if [ -n "$TRANSFERRED_FILE_SIZE" ]; then
    rm -f /tmp/backup2_rsync.txt	# not needed any more
    TRANSFERRED_FILE_UNIT=${TRANSFERRED_FILE_SIZE:$((${#TRANSFERRED_FILE_SIZE}-1))}
    TRANSFERRED_FILE_SIZE=${TRANSFERRED_FILE_SIZE:0:$((${#TRANSFERRED_FILE_SIZE}-1))}
    MULTIPLICAND="1"
    [ "$TRANSFERRED_FILE_UNIT" = "T" ] && MULTIPLICAND="1099511627776"
    [ "$TRANSFERRED_FILE_UNIT" = "G" ] && MULTIPLICAND="1073741824"
    [ "$TRANSFERRED_FILE_UNIT" = "M" ] && MULTIPLICAND="1048576"
    [ "$TRANSFERRED_FILE_UNIT" = "K" ] && MULTIPLICAND="1024"
    [ -n "$DEBUG" ] && echo "TRANSFERRED_FILE_SIZE: $TRANSFERRED_FILE_SIZE, TRANSFERRED_FILE_UNIT: $TRANSFERRED_FILE_UNIT, MULTIPLICAND: $MULTIPLICAND"
    # record the transferred file size in bytes, if we have something valid
    [[ -n $TRANSFERRED_FILE_SIZE ]] && echo "$TRANSFERRED_FILE_SIZE $MULTIPLICAND `date +"%Y-%m-%d %H:%M:%S"`" | awk '{if ($1*$2 > 0) printf "%16.0f",$1*$2; print " "$3,$4}'>>"/var/log/$THIS-tfs.log"
  else
    echo "Warning: unable to retrieve 'Total transferred file size' from /tmp/backup2_rsync.txt - file retained"
  fi
fi
[ -n "$DEBUG" ] && echo "Debug mode: stage 83"


# remove the snapshot
case $SNAPTYPE in
lvm)
	[ -z "$QUIET" ] && echo -en `date +%H:%M:%S` Umounting and removing source LVM snapshot ${LOCALDEVICE}backup at /mnt/${LOCALMNT}backup
	for (( C=1; C<=4; C++ )) do
		umount ${LOCALDEVICE}backup && break
		# sometimes the umount needs a gap of time before it will work
		sleep 20
	done
	if [ "$C" -gt 4 ]; then
		UMOUNTERR=1
		echo -e "`date +%H:%M:%S` Unable to umount ${LOCALDEVICE}backup"
		echo -e "\nTo fix, do:\msudo umount ${LOCALDEVICE}backup\nsudo lvremove -f ${LOCALDEVICE}backup\nsudo rm -rf /mnt/${LOCALMNT}backup"
	else
		lvremove -f ${LOCALDEVICE}backup>/dev/null
		if [ $? -gt 0 ]; then
			UMOUNTERR=1
			echo -e "\n`date +%H:%M:%S` Unable to lvremove -f ${LOCALDEVICE}backup"
		else
			rm -r /mnt/${LOCALMNT}backup || { UMOUNTERR=1; echo -e "\n`date +%H:%M:%S` Unable to rm -r /mnt/${LOCALMNT}backup"; }
		fi
	fi
	[ -z "$QUIET$UMOUNTERR" ] && echo " - ok" || { [ -z "$QUIET" ] && echo " - FAIL"; }
	;;
btrfs)
	[ -z "$QUIET" ] && echo "`date +%H:%M:%S` Deleting $SNAPTYPE snapshot '$BACKUPFROM'"
	btrfs subvolume delete "$BACKUPFROM" >/dev/null || { echo "`date +%H:%M:%S` Unable to remove btrfs snapshot $BACKUPFROM, aborting" >&2; puttosleep; quit 1; }
	;;
esac

fi # matches 'if [ -n "$FAST" ]; then	# XXY: matches fi below' above

if [ -z "$FAST" -a -z "$TEST" -a "$RSYNCERR" -eq 0 ]; then
 [ -z "$QUIET" ] && echo -e `date +%H:%M:%S`" Mirrored $BACKUPFROM ok, now replacing old data with new at destination:"
 # now a section of code that runs on the destination machine
 # by experiment it seems that if the ssh link is broken during the
 # operation the remote machine will continue running the commands:
 # so successful completion of this operation at the remote end - including
 # poweroff at the end - does not depend on continuous ssh link, however
 # this script waits for completion and will report error if it does not
 # complete - this might well mean the ssh connection was broken, not that
 # there was a problem at the remote end
 ssh $SSHOPTS root@$DESTIP 'read QUIET</tmp/backup2_quiet
	[[ ! -d /home/backup/backup ]] || { echo "Error: /home/backup/backup exists on destination - ls /home/backup is:"; ls /home/backup; echo "Will not attempt to update folders on destination"; exit; }
  mkdir -p /home/backup.old
  for i in $(find /home/backup -maxdepth 1 -mindepth 1 -type d -not -iname backup); do \
  [ -z "$QUIET" ] && echo "  `date +%H:%M:%S` - `basename $i`"
  if [[ -d "/home/`basename $i`" ]]; then
   mv "/home/`basename $i`" "/home/backup.old/`basename $i`"
  else
   mkdir -p "/home/backup.old/`basename $i`" # to pass next test
  fi
  if [[ -d "/home/backup.old/`basename $i`" && ! -d "/home/`basename $i`" ]]; then
   mv $i "/home/`basename $i`"
   if [[ -d "/home/`basename $i`" ]]; then
    rm -r "/home/backup.old/`basename $i`"
    if [ -e "/home/backup.old/`basename $i`" ]; then
     echo A problem occurred deleting /home/backup.old/`basename $i`; break
    fi
   else
    echo A problem occurred moving new $i to /home/`basename $i`; break
   fi
  else
   echo A problem occurred moving old /home/`basename $i` to \
   /home/backup.old/`basename $i`; break
  fi
  done
  # tidy up by removing backup folders unless non-empty
  if [ -z "`ls /home/backup 2>&1`" ]; then
   [ -z "$QUIET" ] && echo "  `date +%H:%M:%S` - removing destination /home/backup"
   rm -r /home/backup
  fi
  if [ -z "`ls /home/backup.old 2>&1`" ]; then
   [ -z "$QUIET" ] && echo "  `date +%H:%M:%S` - removing destination /home/backup.old"
   rm -r /home/backup.old
  fi
  rm /tmp/backup2_quiet' 2>/dev/null
  # end of remote execution code
  puttosleep
else
  # failed sync, poweroff - may still be some data in destination /home/backup
  puttosleep
  if [ -z "$FAST" -a -z "$TEST" ]; then
    echo "`date +%H:%M:%S`  A problem occurred mirroring /home to destination $DESTIP"
    echo "         - so no changes were made to /home at destination $DESTIP"
  fi
fi

[ -z "$DEBUG" ] && rm -f /tmp/backup2_*
#closing message
END=`date +"%d/%m/%Y %H:%M:%S"`
if [ -z "$QUIET" ]; then
	echo "`date +%H:%M:%S` Completed ${MODIFIERLC}data mirroring to destination at $END"
	[ -n "$VERBOSE" ] && echo -e "         [Started ${STARTDATETIME}]"
fi
if [ -n "$UMOUNTERR" ]; then
	echo "`date +%H:%M:%S` Note: There was an unresolved problem umounting ${LOCALMNT}backup!"
	quit 1
fi
if [[ $RSYNCERR == "0" ]]; then
	# record completion time for this successful backup
	echo $(date +"%F %T"),$(date +"%Y%m%d%H%M.%S"),$DESTIP >>/var/log/$THIS.log
fi
quit 0
