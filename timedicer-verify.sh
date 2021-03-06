#!/bin/bash
VERSION="2.54 [29 Mar 2016]"
LVMDELETESNAPSHOT="`dirname $0`/lvm-delete-snapshot.sh"
function removesnapshot () {
if [ -n "$BASEFSVOL" -a -n "$BASEFS" ]; then
	if [ -x "$LVMDELETESNAPSHOT" ]; then
		[ -n "$VERBOSE" ] && echo "`date +%H:%M:%S` Deleting LVM snapshot of $BASEFSVOL at $BASEFSVOL$THIS-$$ (if any)"
		"$LVMDELETESNAPSHOT" -f "$BASEFS$THIS-$$" >/dev/null||{ echo "A problem occurred running $LVMDELETESNAPSHOT, aborting">&2; exit 1; }
	else
		echo "Unable to locate $LVMDELETESNAPSHOT, aborting">&2; exit 1
	fi
fi
}

function set_userdir () {
	[ -n "$USELVM" ] && BASEFSVOL=`lvs --noheadings|grep -E -m 1 "(root|home)"|awk '{print "/dev/"$2"/"$1}' 2>/dev/null`
	if [ -n "$BASEFSVOL" ]; then
		# we can use LVM snapshot
		BASEFS=`echo $BASEFSVOL|awk -F/ '{print $NF}'`
		#[ -n "$VERBOSE" ] && echo "Using LVM snapshot as source"
		if [ `echo $BASEFSVOL|awk -F/ '{print NF}'` != 4 ]; then
			# lv should be in the form /dev/xx/$BASEFS
			echo "`date +%H:%M:%S` couldn't identify $BASEFS volume name (found '${BASEFSVOL}'), aborting..."
			exit 1
		fi
		removesnapshot
		if [ -z "$QUIET" ]; then echo -n "`date +%H:%M:%S` Making LVM snapshot of $BASEFSVOL as $BASEFSVOL$THIS-$$"; fi
		# 7Jun12: try with --permission rw instead of previous --permission r, and size 16G instead of 4G
		lvcreate --permission rw --size 16G --snapshot --name $BASEFS$THIS-$$ $BASEFSVOL>/dev/null||{ echo -e "\ncouldn't create logical volume $BASEFSVOL$THIS-$$, aborting..."; exit 1; }
		[ -z "$QUIET" ] && echo -en " - ok\n`date +%H:%M:%S` Mounting LVM snapshot at /mnt/$BASEFS$THIS-$$"
		mkdir -p /mnt/$BASEFS$THIS-$$ || { echo -e "\ncouldn't create mountpoint, aborting..."; exit 1; }
		sleep 2s # prevent error 'special device ... does not exist' when mounting
		mount -o ro "$BASEFSVOL$THIS-$$" "/mnt/$BASEFS$THIS-$$"||{ echo -e "\ncouldn't mount $BASEFSVOL$THIS-$$ at mountpoint, aborting..."; exit 1; }
		[ -z "$QUIET" ] && echo " - ok"
		USERDIR="/mnt/$BASEFS$THIS-$$"
		if [ -d "$USERDIR/home" ]; then USERDIR="${USERDIR}/home"; fi
	else
		USERDIR="/home"
		unset BASEFSVOL
	fi
}

function verifysession() {
	#local ATTIME=`sed -n "$1p" "/tmp/$THIS-$$.sessions"`
	# decide whether to skip
	local THISREPOERR=0
	if [ -n "$VERBOSE" ]; then
		echo -en "\n    `date +%H:%M:%S`: $1 $ATTIME: Starting"
	elif [ -z "$QUIET" ]; then
		echo -n "."
	fi
	[ -n "$TEMPORARYDIR" ] && SETTEMPDIR=--tempdir
	# add this verification session to run file so other processes can tell this verification is underway
	[[ -n $ALTERNATE ]] && echo -e "# adding $REPO,$ATTIME - at $(date +"%F %T")\n$REPO,$ATTIME" >>"/tmp/$THIS-live-$$.run"
	rdiff-backup --verify-at-time $ATTIME $SETTEMPDIR $TEMPORARYDIR "$REPO" 1>"/tmp/$THIS-$$-$1-errmsg1.txt" 2>&1
	RDIFFBACKUPERR=$?
	[[ -n $ALTERNATE ]] && sed -i '/^'"${REPO//\//\\/},$ATTIME"'$/{s/^/# ending /;s/$/ - at '"$(date +"%F %T")"'/}' "/tmp/$THIS-live-$$.run"
	# exit code (RDIFFBACKUPERR) depends on my modified compare.py - the original sets exit code to the number of
	# errors, and unfortunately an aborted process also generates an exit code of 1. My modified compare.py gives
	# exit code 2 if any verification errors occurred, and outputs a corresponding message;
	# this gives us two ways to confirm that the verification run actually finished and wasn't aborted, whereas original
	# code gave us none. We use the exit code but check the text is as expected too.
	# If error code is not 0 or 2 we regard it as fatal.
	#
	# notes to self::
	# diff -u0 /opt/rdiff-backup-orig/compare.py /usr/share/pyshared/rdiff_backup/compare.py | tee /opt/compare.py.diff # create patch
	# sudo patch /usr/share/pyshared/rdiff_backup/compare.py </opt/compare.py.diff	# apply patch
	if [ $RDIFFBACKUPERR -gt 0 ]; then
		if [ $RDIFFBACKUPERR -eq 2 ]; then
			# error 2 means one or more files could not be verified but we should compare output text against
			# $IGNORESFILE and also certain common messages and see if we are left with anything else
			grep -vxFf "$IGNORESFILE" "/tmp/$THIS-$$-$SESSION-errmsg1.txt"|sed '/^$/d;/^Not all files could be verified.$/d;/^Warning: Access Control List file not found$/d;/^Warning: Extended Attributes file not found$/d;/^Your backup repository may be corrupted!$/d;/^A regular file was indicated by the metadata, but could not be$/{N;N;N;N;d}'>"/tmp/$THIS-$$-$SESSION-errmsg2.txt"
			# this message is generated by modified compare.py
			grep "Not all files could be verified" "/tmp/$THIS-$$-$SESSION-errmsg1.txt" >/dev/null || echo -e "\nn    `date +%H:%M:%S`: $1 $ATTIME: FAILED with error 2 but missing 'Not all files could be verified' text" >&2
		fi
		if [ -s "/tmp/$THIS-$$-$SESSION-errmsg2.txt" -o $RDIFFBACKUPERR -ne 2 ]; then
			echo -e "\n    `date +%H:%M:%S`: $1 $ATTIME: FAILED with error $RDIFFBACKUPERR"
			[ -s "/tmp/$THIS-$$-$SESSION-errmsg1.txt" ] && cat "/tmp/$THIS-$$-$SESSION-errmsg1.txt"
			echo -e "\n$REPO session $ATTIME failed verification\n">&2
			THISREPOERR=1
			REPOERR=$(($REPOERR+1))
			echo "$SESSION failed">>"/tmp/$THIS-$$-failed.txt"
		elif [ -n "$VERBOSE" ]; then
			echo -en "\n    `date +%H:%M:%S`: $1 $ATTIME: Error $RDIFFBACKUPERR treated as ignorable"
		fi
	else
		[[ -n $VERBOSE ]] && echo -en "\n    `date +%H:%M:%S`: $1 $ATTIME: OK"
		grep "Every file verified successfully" "/tmp/$THIS-$$-$SESSION-errmsg1.txt" >/dev/null || echo -e "\nn    `date +%H:%M:%S`: $1 $ATTIME: but missing 'Every file verified successfully' text" >&2
	fi
	if [ "$THISREPOERR" -eq 1 ]; then
		# delete this repo from the verify list if it was there and if this was a genuine (exit code 2) verification failure
		# (we don't delete if exit code 1 cos it might just be an abort which would have verified successfully if it had
		#  been allowed to run to completion)
		[[ -s "$ORIGD/verified.log" && $RDIFFBACKUPERR -ne 1 ]] && sed -i "/$ATTIME/d" "$ORIGD/verified.log"
	else
		# if we've completed a successful verification and there were previous faked verifications, now add them to
		# the verified.log
		[[ -s "$ORIGD/verified-fake.log" ]] && cat "$ORIGD/verified-fake.log" >>"$ORIGD/verified.log" && rm "$ORIGD/verified-fake.log"
		# record successful verification. If it is the most recent session, precede the datetime record with 'R'
		# - when/if this is no longer the most recent session it should be verified again
		[ $1 -eq $SESSIONS ] && local GREPADD="R"
		echo "$GREPADD$ATTIME,`date +"%F %T"`,$RDIFFBACKUPERR">>"$ORIGD/verified.log" || echo -e "\nUnable to write to '$ORIGD/verified.log' to '$VNAME'">&2
		local VNAME="`stat -c %U $ORIGD`"
		if [ "$VNAME" != "`stat -c %U $ORIGD/verified.log`" ]; then
			chown "$VNAME:" "$ORIGD/verified.log" || echo -e "\nUnable to set ownership of '$ORIGD/verified.log' to '$VNAME'">&2
		fi
	fi
}

THIS=`basename $0`
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
ACTION="Verify"
# by default set number of concurrent processes to 1 (previously: number of CPUs or cores)
#CONCURRENT=`cat /proc/cpuinfo | grep processor | wc -l`
CONCURRENT=1
INCFAKE="F\?"
while getopts ":a:bc:d:efhilmn:qrst:vu:wx:z:12345:6" optname; do
	case "$optname" in
		"a")	ABORTAT=$(date +%s -d "$OPTARG" || { echo "Invalid -a date format, aborting" >&2; exit 1; });;
		"b")	RDIFFWEBFIX="y";;
		"c")	CONCURRENT="$OPTARG";;
		"d")	TODATE="$OPTARG";;
		"e")	DEBUG="y";;
		"f")	FULL="y";;
		"h")	HELP="y";;
		"i")	CONTINUE_ON_ERROR="y";;
		"l")	CHANGELOG="y";;
		"m")	USELVM="y";;
		"n")	ARCHIVENAME="$OPTARG";;
		"q")	QUIET="y";;
		"r")	RETEST="y"; unset INCFAKE;;
		"s")	SHOWONLY="y";ACTION="Show";;
		"t")	TEMPORARYDIR="$OPTARG";;
		"u")	FORUSER="/$OPTARG";;
		"v")	VERBOSE="y";;
		"w")	COLUMNS="9999";;
		"x")	ARCHIVENAME="$OPTARG"; UNMATCH="y";;
		"z")	DOLAST="$OPTARG";;
		"1")	ONLYOLDEST="y";;
		"2")	SKIPMOSTRECENT="y";;
		"3")	ALTERNATE="y";;
		"4")	SKIPNFAKE="y";;
		"5")	SKIPNFAKE="y";FORCEOLDEST="$OPTARG";;
		"6")	unset INCFAKE;;
		"?")	echo "Unknown option $OPTARG"; exit 1;;
		*)		echo "Unknown error while processing options"; exit 1;;
	esac
done
shift $(($OPTIND-1))
[ -z "$QUIET" -o -n "$HELP" -o -n "$CHANGELOG" ] && echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -n "$HELP" ]; then
	echo -e "Verifies integrity of rdiff-backup repositories at \
/home/*/[here] and /home/*/*/[here]. \
Unless options -f or -d are used it just verifies the most recent session \
(before the last one) in each repository. With -f or -d options it may take \
a long time!

If run by root (or with sudo) $THIS checks repositories for all users (as \
restricted by -u, -n and -x options), otherwise it checks only the current \
user's repositories. A non-zero exit code is returned \
if one or more problems were found.

Each successful verification for a repository session is saved in that \
repository's rdiff-backup-data/verified.log file, on a subsequent run \
that session is skipped for verification unless -r option is used. This file \
therefore provides a linear record of successful verifications in the form \
[datetime-of-original-session],[datetime-when-verified],[rdiff-backup exit code].

You can override problem detection (if you have a known reported problem \
which is not in fact such or you do not consider fatal) by adding the \
error text to /opt/$THIS-ignore.txt, any \
whole line matches for such text will be ignored on future runs.

Normally $THIS will exit immediately if rdiff-backup reports an error \
(unless the error text is matched in /opt/$THIS-ignore.txt), but you \
can override this behaviour with -i option.

Also with -b option it fixes ownership of restore.log files \
(which rdiffWeb may have created and set to root ownership, thus \
causing warning errors upon user trying to retrieve files).

$THIS requires a small modification to rdiff-backup in compare.py - this is \
applied automatically (unless already present) and a warning printed if it \
fails. The modification ensures that if a verification fails rdiff-backup \
exits with a warning text and exit code 2; so $THIS can \
distinguish between such cases (which may, subject to the contents of \
/opt/$THIS-ignore.txt, be ok), and an aborted or crashed rdiff-backup \
session (exit code 1).

$THIS is part of the TimeDicer Server software suite.

Usage:\t $THIS [options]

Options:
  -a [datetime] - stop (abort) verifications at datetime (with exit code 0) *
  -b - fix ownership of any rdiffweb-created restore.log files
  -c [number] - maximum number of concurrent verify sessions (default 1) - \
specifying a higher number may speed up operations provided your system does \
not become cpu/memory/io bound in which case it may be slower (it also \
increases the risk of running out of temporary disk space)
  -d [datetime] - verify backup sessions back to session on, or next before, datetime *
  -e - debug mode (unexpected things may happen)
  -f - verify all sessions in each repository (slowest)
  -h - show this help and quit
  -i - continue after rdiff-backup reports an error (aka 'ignore')
  -l - show changelog and quit
  -m - create and use lvm snapshot of source data (discarded at end)
  -n [name] - check only repositories containing text 'name' in their pathname (cf. -x)
  -q - quiet (text output only on error)
  -r - don't skip any repository sessions previously verified as ok
  -s - list backup sessions and date/time of the corresponding previous verification session (if any), then quit
  -t [tmpdir] - use tmpdir for temporary storage
  -u [user] - only for named user (ignored unless run by root)
  -v - verbose output
  -x [name] - skip any repositories containing text 'name' in their pathname (cf. -n)
  -z [name] - process any repositories with path containing text 'name' last
  -1 - verify only the earliest session for each repository that falls \
within the specification (cf. -4,-5)
  -2 - skip verification of the most recent session for each repository
  -3 - skip any verifications that are in progress elsewhere, normally in a different \
session on the same machine, but with an additional script can also detect \
sessions in progress on another (i.e. mirror) machine
  -4 - skip all verifications that would be performed for each repository \
except the earliest and instead mark them in that repo's verified.log as \
having been performed but with a special 'fake' flag. Sessions thus marked \
will be skipped on any subsequent run of $THIS for this repository \
unless -6 or -r is specified. In effect this is the same as running $THIS -1, \
or running rdiff-backup \
--verify for the earliest verification date, but it affects future runs \
of $THIS. Marking of fake sessions in verified.log only occurs if and after \
successful verification of the earliest session, or confirmation of a \
previous successful verification of the earliest session.
  -5 [datetime] - as -4 but perform an actual verification for the earliest \
session even if it was previously successfully verified but such \
verification was performed before [datetime] *
  -6 - don't skip over 'fake' former verifications (see -4,-5)

* datetime can be but does not have to be in the format used by \
rdiff-backup; it just needs to be understood by the 'date' command \
e.g. yesterday, \"3 July 2012\", \"2 weeks ago\", \
\"2012-05-03 14:26\". See 'man date' for more details.

Why $(basename $THIS .sh):
rdiff-backup provides the --verify-at-time option to verify a single \
repository session. However this does not verify any intermediate sessions. \
For instance, a file that did *not* exist \
at the time of the earlier session, *did* exist at the time of an intermediate \
session, but has subsequently been deleted, could prove irrecoverable even \
when the earlier session had been verified.

The only way to be confident about all repository sessions is to use \
rdiff-backup's --verify-at-time option to verify each session individually. \
This is what \
$THIS accomplishes, and although it may be a slow process, by running \
verification sessions concurrently and by keeping a record of successful \
previous verifications and not (unless required by -r or -5 options) rechecking \
them, it becomes manageable. A suggested use is as a weekly cron \
job with -d \"one month ago\" option (sessions earlier than a week ago will \
normally be skipped automatically because they were verified previously).

Dependencies: awk bash column coreutils diff findutils grep lvm(optional) \
$(basename $LVMDELETESNAPSHOT)(optional) rdiff-backup sed

License: Copyright 2016 Dominic Raferd. Licensed under the Apache License, \
Version 2.0 (the \"License\"); you may not use this file except in compliance \
with the License. You may obtain a copy of the License at \
http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable \
law or agreed to in writing, software distributed under the License is \
distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY \
KIND, either express or implied. See the License for the specific language \
governing permissions and limitations under the License.
"|fold -sw $COLUMNS
fi
if [ -n "$CHANGELOG" ]; then
	# changelog
	[ -n "$HELP" ] && echo "Changelog:"
	echo -e "\
2.54 [29 Mar 2016] - serious bugfix - v2.25-2.53 were failing to detect many verification failures
2.53 [25 Feb 2016] - bugfix unnecessary re-verification of single session repos with -d
2.52 [12 Feb 2016] - bugfix -5 option
2.51 [29 Jan 2016] - add -5 option (renumber previous -5 as -6)
2.50 [13 Jan 2016] - add -4 and -5 options ('fake' verifications)
2.49 [17 Dec 2015] - add automatic patching of rdiff_backup/compare.py
2.48 [16 Dec 2015] - bugfix -z option
2.47 [15 Dec 2015] - add -z option
2.46 [15 Dec 2015] - bugfix -3 option
2.45 [14 Dec 2015] - add -3 option
2.44 [12 Dec 2015] - bugfix -a option
2.43 [09 Dec 2015] - add -a option
2.42 [30 Nov 2015] - bugfix for error detection, depends on modified \
compare.py, bugfix for -1 option
2.41 [19 Nov 2015] - bugfix for -1 option
2.40 [16 Nov 2015] - treat non-zero exitcode <> 2 from rdiff-backup as fatal \
(fix bug whereby killing/aborting process - exit code 1 - set a success \
'flag' for the, in fact incomplete, verification action)
2.30 [08 Nov 2015] - add -1 option
2.26 [29 Oct 2015] - default concurrent sessions = 1
2.25 [21 Oct 2015] - add -e debug mode, bugfix use of /opt/$THIS-ignore.txt
2.24 [04 Oct 2015] - abort if an instance of $THIS is already running as a different process
2.23 [14 Jan 2015] - don't touch verified.log file(s) unless need to be updated
2.22 [08 Dec 2014] - bugfix, was not using exit code >0 when error found in \
repository (except the last)
2.21 [11 Oct 2014] - bugfix, was not counting errors that occurred with rdiff-backup --list-increments
2.20 [27 Mar 2014] - use rdiff-backup --list-increments to \
obtain list - avoid checking null increments
2.15 [10 Oct 2013] - tweak snapshot settings to allow concurrent runs of $THIS
2.14 [09 Oct 2013] - changes to text output, reassign -o option to -x
2.13 [19 Sep 2013] - add (-o ->) -x option
2.12 [19 Feb 2013] - web help layout fix, reassign -w to -b
2.10 [09 Jul 2012] - first public release
2.04 [10 Jun 2012] - improved concurrency
2.03 [09 Jun 2012] - add -c, -m, -n, -t options
2.02 [06 Jun 2012] - bugfixes
2.0105 [05 Jan 2012] - hide lvremove non-error text on removing snapshot
1.1230 [30 Dec 2011] - (create and) use /home/tmp as TMPDIR, add -l option to show this changelog
1.0818 [18 Aug 2011] - add use of LVM snapshot if available (for root only), add -u and -d options
1.0817 [17 Aug 2011] - add non-root usage, add -s option "|fold -sw $COLUMNS
fi
[ -n "$HELP$CHANGELOG" ] && exit 0
[ -n "$DEBUG" ] && echo "Debug mode"
if [ -n "$TODATE" ]; then
	[ -n "$FULL" ] && { echo "Incompatible options -f and -d, aborting...">&2; exit 1; }
	TODATEEPOCH=`date -d "$TODATE" +%s 2>/dev/null`
	# reject invalid dates or dates before 1/1/2005
	[ "$TODATEEPOCH" -ge 1104537600 2>/dev/null ] || { echo "Invalid date '$TODATE' on command line, aborting...">&2; exit 1; }
fi
if [ -n "$FORCEOLDEST" ]; then
	FORCEEPOCH=`date -d "$FORCEOLDEST" +%s 2>/dev/null`
	# reject invalid dates or dates before 1/1/2005
	[ "$FORCEEPOCH" -ge 1104537600 2>/dev/null ] || { echo "Invalid date '$FORCEOLDEST' on command line, aborting...">&2; exit 1; }
fi
if [ "$(id -u)" != "0" ]; then
	unset FORUSER
	THISUSER="$USER"
	USERDIR="/home/$USER"
	ORIGUSERDIR="$USERDIR"
	USERTEXT="${USER}'s"
else
	THISUSER="root"
	ORIGUSERDIR="/home"
	if [ -z "$FORUSER" ]; then
		USERTEXT="all users'"
	else
		if [ ! -d "/home/$FORUSER" ]; then
			echo "Can't find home directory for user $FORUSER, aborting"
			exit 1
		fi
		USERTEXT="${FORUSER}'s"
	fi
	set_userdir
fi
PRIOR="$(ps --no-headers -wwAo "s,pid,ppid,sid,args" -C "$THIS" |sed -n "/${THIS:0:1}\\${THIS:1} /{/^[XZ] /d;/ $$ /d;/ $PPID /d;p}")"
[[ -n $PRIOR ]] && { echo -e "$THIS is already running:\n$PRIOR\nOur PID/PPID: $$,$PPID\nAborting...">&2; exit 1; }
SKIPPEDVSESSIONSTOTAL=0; VSESSIONSTOTAL=0
PREVFAKEDVSESSIONSTOTAL=0; FAKEDVSESSIONSTOTAL=0
if [ -n "$VERBOSE" ]; then
	echo "`date +%H:%M:%S` ${ACTION}ing $USERTEXT rdiff-backup repositories at $ORIGUSERDIR$FORUSER"
elif [ -z "$QUIET" ]; then
	echo "${ACTION}ing repositories at $USERDIR"
fi

VER=`rdiff-backup --version 2>&1`
[ -z "$VER" -a ! -x "rdiff-backup" ] && echo "Unable to run rdiff-backup, aborting...">&2 && exit 1

# $THIS really needs a patched compare.py, this checks if done, applies patch if not and checks it is ok
# however it continues even if the patch cannot be applied
while :; do
	if [[ -s /usr/share/pyshared/rdiff_backup/compare.py ]]; then
		grep "Not all files could be verified" /usr/share/pyshared/rdiff_backup/compare.py >/dev/null && { [[ -n $VERBOSE ]] && echo "rdiff_backup/compare.py is patched ok"; break; }
		# create patch file on the fly
		echo '--- compare.py  2015-11-30 17:12:56.046174495 +0000
+++ compare.py  2015-11-30 17:16:23.978174495 +0000
@@ -101,2 +101,5 @@
-       if not bad_files: log.Log("Every file verified successfully.", 3)
-       return bad_files
+       if bad_files:
+               log.Log("Not all files could be verified.", 3)
+               return 2
+       log.Log("Every file verified successfully.", 3)
+       return 0' >/tmp/compare.py.diff || { echo "Could not create /tmp/compare.py.diff, aborting" >&2; exit 1; }
		patch -sN -r- /usr/share/pyshared/rdiff_backup/compare.py </tmp/compare.py.diff && echo "rdiff_backup/compare.py patched to give exit code 2 on any verification failure" || { echo "Warning: rdiff_backup/compare.py could not be patched!" >&2; [[ $THISUSER != "root" ]] && echo "To fix this, try running $THIS as root or with sudo" >&2; break; }
	else
		echo "Warning: unable to check if rdiff_backup/compare.py is patched (it probably isn't)" >&2; break
	fi
done

if [ -z "$QUIET" ]; then
	echo "Maximum of $CONCURRENT concurrent verification operations"
	if [ -z "$SHOWONLY" ]; then
		if [ -n "$ARCHIVENAME" ]; then
			echo -n "Checking only repositories with"
			[ -n "$UNMATCH" ] && echo -n "out"
			echo " '$ARCHIVENAME' in pathname"
		fi
		if [ -n "$FULL" ]; then
			echo -e "Verification of all sessions in each repository"
		elif [[ -n $TODATE ]]; then
			echo -e "Verification of sessions back to $TODATE from each repository"
		else
			echo -e "Verification of most recent session in each repository"
		fi
		if [[ -n $ONLYOLDEST ]]; then
			echo "  - filtered for only the earliest such session"
		fi
		[[ -n $ABORTAT ]] && echo "Will abort if still running at $(date -d @$ABORTAT +"%F %T")"
		[[ -n $ALTERNATE ]] && echo "Skipping verifications that are underway elsewhere"
		[[ -n $SKIPNFAKE ]] && echo "Skipping verifications except the earliest and marking such as 'fake' verified"
		[[ -n $FORCEOLDEST ]] && echo " - forcing verification of earliest if last verified before $FORCEOLDEST"
		[[ -z $INCFAKE ]] && echo "Not skipping previously 'faked' verifications"
		[[ -n $DOLAST ]] && echo "Repositories with path containing '$DOLAST' will be processed last"
		[[ -n $TEMPORARYDIR ]] && echo -e "Using tempdir $TEMPORARYDIR"
		echo -e "This may take a long time! Please be patient..."
		if [[ -z $RETEST ]]; then
			echo "Skipping previously verified sessions"
			if [ -z "$VERBOSE" ]; then
				echo -e "  . indicates session that is undergoing/has undergone current verification\n  - indicates session skipped because previously verified"
				[[ -n $ALTERNATE ]] && echo -e "  ' indicates session skipped because it is being verified elsewhere"
				[[ -n $SKIPMOSTRECENT ]] && echo "  + indicates session skipped because it is the most recent"
				[[ -n $SKIPNFAKE ]] && echo "  F indicates session skipped and 'fake' verified"
				[[ -n $INCFAKE ]] && echo "  f indicates session skipped because previously 'fake' verified"
			fi
		fi
	else
		echo "Note: If 'Most_Recent_Only' shows 'y', then this \
has only been verified as the most recent session and it will be \
retested for full verification when $THIS is re-run after a subsequent \
backup session."|fold -s -w $COLUMNS
	fi
fi
# if basearchive in TimeDicer configuration file is blank then depth will be 3,
#   i.e. repositories are at /home/[user]/[repository]
# if basearchive is one folder deep (e.g. archives/) then depth will be 4,
#   i.e. repositories are at /home/[user]/[basearchive]/[repository]
# - to cover both possibilities use -mindepth 3 -maxdepth 4
[ -n "$DEBUG" ] && echo -e "MYPID    : $$\nBASEFSVOL: $BASEFSVOL\nBASEFS   : $BASEFS\nSearching $USERDIR$FORUSER for repositories"
[ -z "$SHOWONLY$QUIET" ] && echo -n "`date +%H:%M:%S` "
[ -z "$QUIET" ] && echo -n "Total repositories found: "
if [ -z "$UNMATCH" ]; then
	find "$USERDIR$FORUSER" -mindepth 2 -maxdepth 4 -type d -regex .*"$ARCHIVENAME".*rdiff-backup-data 2>/dev/null|sort >"/tmp/$THIS-$$.repos"
else
	find "$USERDIR$FORUSER" -mindepth 2 -maxdepth 4 -type d ! -regex .*"$ARCHIVENAME".* -regex .*rdiff-backup-data 2>/dev/null|sort >"/tmp/$THIS-$$.repos"
fi
[[ -n $DOLAST ]] && sed -i "/${DOLAST//\//\\/}"'/{H;d};${G;s/\n//}' "/tmp/$THIS-$$.repos"
REPOTOTAL=`cat "/tmp/$THIS-$$.repos"|wc -l`
REPOERRTOTAL=0
[[ -n $DEBUG ]] && echo "got here 123"
[ -z "$QUIET" ] && { echo -n "$REPOTOTAL"; [ -n "$SHOWONLY" ] && echo; }
REPONUM=0
VSESSIONSABORTED=0
IFS=$'\n'
WHEN=`date --rfc-3339=seconds|sed 's/ /T/'`
IGNORESFILE="/tmp/$THIS-$$-ignore.txt"
if [ -s "/opt/$THIS-ignore.txt" ]; then
	cp "/opt/$THIS-ignore.txt" "$IGNORESFILE"
else
	rm -f "$IGNORESFILES"; touch "$IGNORESFILE"
fi
[[ -n $DEBUG ]] && echo "got here 133"
for D in `cat "/tmp/$THIS-$$.repos"`; do
	[[ -n $DEBUG ]] && echo "got here 143"
	REPOERR=0
	[ $REPOERRTOTAL -gt 0 -a -z "$CONTINUE_ON_ERROR" ] && break
	[[ -n $ABORTAT && $(date +%s) -ge $ABORTAT ]] && { [[ -n $VERBOSE ]] && echo -e "\n`date +%T`: abort timeout reached"; break; }
	REPO=`echo $D|sed 's@\(.*\)/.*@\1@'`
	if [ -n "$BASEFSVOL" ]; then
		ORIGD="/$BASEFS${D:${#USERDIR}}"
		ORIGREPO="/$BASEFS${REPO:${#USERDIR}}"
	else
		ORIGD=$D; ORIGREPO=$REPO
	fi
	[[ -n $DEBUG ]] && echo "got here 153"
	[[ -n $SKIPNFAKE ]] && { [[ -n $DEBUG ]] && echo "got here 154"; echo -n >"$ORIGD/verified-fake.log" || { echo -e "\nUnable to write to '$ORIGD/verified-fake.log'">&2; exit 1; } }
	[[ -n $DEBUG ]] && echo "got here 155"
	REPONUM=$(($REPONUM+1))
	[ -n "$DEBUG" ] && echo -e "\nD        : $D\nREPO     : $REPO\nORIGD    : $ORIGD\nORIGREPO : $ORIGREPO\nREPONUM  : $REPONUM"
	if [ -z "$QUIET" ]; then
		echo
		[ -z "$SHOWONLY" ] && echo -en "  `date +%H:%M:%S` "
		echo -en "$REPONUM/$REPOTOTAL "
	fi
	[[ -n $DEBUG ]] && echo "got here 163"
	[ -z "$QUIET" -o -n "$SHOWONLY" ] && echo -n "\"$ORIGREPO\""
	rdiff-backup --list-increments "$REPO" >"/tmp/$THIS-$$.sessions" || { let REPOERRTOTAL++; continue; }
	sed -i '/increments\./{s/.*increments\.//;s/\.dir.*//;p};d' "/tmp/$THIS-$$.sessions"
	# add the most recent session using the actual datetime
	find "$REPO/rdiff-backup-data" -maxdepth 1 -type f -name "session_statistics.*.data"|grep -E -o "20[0-9]{2}-[0-9]{2}-[0-9]{2}[^.]*"|sort|tail -n 1 >>"/tmp/$THIS-$$.sessions"
	SESSIONS=`wc -l "/tmp/$THIS-$$.sessions"|awk '{print $1}'`
	if [ -z "$SHOWONLY" ]; then
		if [ -n "$FULL" ]; then
			[[ -n $ONLYOLDEST ]] && sed -i '2,$d' "/tmp/$THIS-$$.sessions" && SESSIONS=1
			LASTSESSION=1; FIRSTSESSION=$SESSIONS
			[ -z "$QUIET" ] && echo -n " - checking all of $SESSIONS sessions"
		elif [ -n "$TODATEEPOCH" ]; then
			FIRSTSESSION=$SESSIONS
			# to work out the last session we look through the session
			# dates in reverse order and find the first one that is on or
			# before date, this does it in one (rather complex) line:
			COUNTER=0; REVERSELIST=`tac "/tmp/$THIS-$$.sessions"`
			for LINE in $REVERSELIST; do
				let COUNTER++
				echo -n $LINE|sed 's/T/ /'|xargs -I {} date +"%s" -d {}|xargs -I {} test $TODATEEPOCH -ge {} && break
			done
			LASTSESSION=$(($SESSIONS-$COUNTER+1))
			if [[ -n $ONLYOLDEST ]]; then
				FIRSTSESSION=$LASTSESSION
				[[ -z $QUIET ]]  && echo -n " - checking earliest session within the date span"
			elif [[ -z $QUIET ]]; then
				echo -n " - checking most recent $COUNTER of $SESSIONS sessions"
			fi
		else
			LASTSESSION=$SESSIONS; FIRSTSESSION=$LASTSESSION
			[ -z "$QUIET" ] && echo -n " - checking most recent 1 of $SESSIONS sessions"
		fi
	else
		echo
		echo "Num,Backup_Session_When,Verified_When,Most_Recent_Only">"/tmp/$THIS-$$-sessions.csv"
		REVERSELIST=`tac "/tmp/$THIS-$$.sessions"`
		LINENUM=0
		for LINE in $REVERSELIST; do
			let LINENUM++
			if [ -s "$ORIGD/verified.log" ]; then
				if [ $LINENUM -eq 1 ]; then
					LINEFOUND="`grep "$LINE" "$ORIGD/verified.log"`"
				else	#skip any 'R' sessions except the most recent cos irrelevant
					LINEFOUND="`grep --color=NEVER "^$LINE" "$ORIGD/verified.log"`"
				fi
				if [ -n "$LINEFOUND" ]; then
					LINE="$LINEFOUND"
					if [ "${LINE:0:1}" = "R" ]; then
						LINE="${LINE:1:999},y"
					fi
				fi
			fi
			echo "$LINENUM,${LINE/T/ }">>"/tmp/$THIS-$$-sessions.csv"
		done
		column -s, -t "/tmp/$THIS-$$-sessions.csv"
		continue
	fi
	if [[ -z $QUIET ]]; then
		echo -n " ("
		if [[ -z $VERBOSE ]]; then
			echo -n "$(sed -n "${FIRSTSESSION}p" "/tmp/$THIS-$$.sessions") "
			[[ $LASTSESSION -ne $FIRSTSESSION ]] && echo -n " "
		fi
		[[ $LASTSESSION -ne $FIRSTSESSION ]] && echo -n "to $(sed -n "${LASTSESSION}p" "/tmp/$THIS-$$.sessions")"
		echo -n "): "
	fi
	# now loop through the sessions for this repository
	for ((SESSION=$FIRSTSESSION; SESSION>=$LASTSESSION; SESSION--)); do
		[ "$REPOERR" -gt 0 -a -z "$CONTINUE_ON_ERROR" ] && break
		# decide whether to skip
		ATTIME=`sed -n "${SESSION}p" "/tmp/$THIS-$$.sessions"`
		# if on most recent session accept a prevous verify session preceded by R
		[ $SESSION -ne $SESSIONS ] && GREPPRC="^" || GREPPRC=""
		[ ! -f "$ORIGD/verified.log" ] && touch "$ORIGD/verified.log"
		if [[ -n $FORCEOLDEST && $SESSION == $LASTSESSION ]]; then
			SESSIONT=$(grep "$GREPPRC$ATTIME" "$ORIGD/verified.log" 2>/dev/null|awk -F, '{print $2}'|sort -n|tail -n1)
			if [[ -n $SESSIONT ]]; then
				SESSIONEPOCH=$(date -d "$SESSIONT" +%s 2>/dev/null)
				[[ -n $VERBOSE ]] && echo -en "\n    Last session: last verified $SESSIONT"
			else
				SESSIONEPOCH=0
				[[ -n $VERBOSE ]] && echo -en "\n    Last session: no previous verification found"
			fi
			if [[ $SESSIONEPOCH -lt $FORCEEPOCH ]]; then
				FORCINGOLDEST="y"
				[[ -n $VERBOSE ]] && echo -n " - verifying"
			else
				unset FORCINGOLDEST
				[[ -n $VERBOSE ]] && echo -n " - skipping"
			fi
		else
			unset FORCINGOLDEST
		fi
		if [[ $SESSION == $SESSIONS && -n $SKIPMOSTRECENT ]]; then
			let SKIPPEDVSESSIONSTOTAL++
			if [ -n "$VERBOSE" ]; then
				echo -en "\n    `date +%H:%M:%S`: $SESSION $ATTIME: Skipping (most recent session)"
			elif [ -z "$QUIET" ]; then
				echo -n "+"
			fi
		elif [[ -z $RETEST$FORCINGOLDEST && -s "$ORIGD/verified.log" && -n "`grep "$GREPPRC$ATTIME" "$ORIGD/verified.log"`" ]]; then
			let SKIPPEDVSESSIONSTOTAL++
			if [ -n "$VERBOSE" ]; then
				echo -en "\n    `date +%H:%M:%S`: $SESSION $ATTIME: Skipping (previously verified)"
			elif [ -z "$QUIET" ]; then
				echo -n "-"
			fi
		elif [[ -z $RETEST$FORCINGOLDEST && -s "$ORIGD/verified.log" && -n "`grep "$GREPPRC$INCFAKE$ATTIME" "$ORIGD/verified.log"`" ]]; then
			let SKIPPEDVSESSIONSTOTAL++; let PREVFAKEDVSESSIONSTOTAL++
			if [ -n "$VERBOSE" ]; then
				echo -en "\n    `date +%H:%M:%S`: $SESSION $ATTIME: Skipping (previously faked verification)"
			elif [ -z "$QUIET" ]; then
				echo -n "f"
			fi
		elif [[ -z $RETEST$FORCINGOLDEST && -n $SKIPNFAKE && $SESSION != $LASTSESSION ]]; then
			let SKIPPEDVSESSIONSTOTAL++; let FAKEDVSESSIONSTOTAL++
			if [ -n "$VERBOSE" ]; then
				echo -en "\n    `date +%H:%M:%S`: $SESSION $ATTIME: Skipping (faking verification)"
			elif [ -z "$QUIET" ]; then
				echo -n "F"
			fi
			# record fake verification
			echo "F$ATTIME,`date +"%F %T"`">>"$ORIGD/verified-fake.log" || echo -e "\nUnable to write to '$ORIGD/verified-fake.log'">&2
		else
			if [[ -n $ALTERNATE ]]; then
				# search for any other $THIS processes which are running and make sure not to duplicate their current verification
				[[ -n $DEBUG ]] && echo -en "\nDEBUG: ALTERNATE find output: " && find /tmp -maxdepth 1 -name "$THIS-live-*.run" -not -name "$THIS-live-$$.run" -mmin -4 -execdir grep "^$REPO,$ATTIME$" "{}" \+ | awk '{printf $0}'
				ALTERNATEUNDERWAY=$(find /tmp -maxdepth 1 -name "$THIS-live-*.run" -not -name "$THIS-live-$$.run" -mmin -4 -execdir grep "^$REPO,$ATTIME$" "{}" \+ 2>/dev/null)
				[[ -n $DEBUG ]] && echo -e "\nDEBUG: ALTERNATE check: ALTERNATEUNDERWAY='$ALTERNATEUNDERWAY'"
				if [[ -n $ALTERNATEUNDERWAY ]]; then	# we found a match, that means this repo/session is already being verified
					# skip this session
					[[ -n $DEBUG ]] && echo -n "DEBUG: ALTERNATE check: - match found, will skip verification"
					let SKIPPEDVSESSIONSTOTAL++
					if [ -n "$VERBOSE" ]; then
						echo -en "\n    `date +%H:%M:%S`: $SESSION $ATTIME: Skipping (alternate process)"
					elif [ -z "$QUIET" ]; then
						echo -n "'"
					fi
					continue
				elif [[ -n $DEBUG ]]; then
					echo -n "DEBUG: ALTERNATE check: - match not found, will continue with verification"
				fi
			fi
			# start a verify session and return here at once
			verifysession "$SESSION" &
			let VSESSIONSTOTAL++
			# now check if there are already $CONCURRENT sessions in progress, wait if there are
			while true; do
				[ -f "/tmp/$THIS-$$-failed.txt" ] && REPOERR=1 && break
 				RUNNING=($(jobs -rp))
				[ "${#RUNNING[@]}" -lt "$CONCURRENT" ] && break
				# if we have overrun time then get out of here but end all child processes first
				if [[ -n $ABORTAT && $(date +%s) -ge $ABORTAT ]]; then
					for PID in ${RUNNING[@]}; do
						# use kill -- to send TERM, kill -9 to send KILL
						CHILDPID=$(ps --no-headers --ppid $PID -o pid)
						[[ -n $VERBOSE ]] && echo -en "\n    `date +%T`: abort timeout reached: killing pid '$PID'\n    "
						kill -- $PID
						sleep 15s
						if [[ -n $CHILDPID ]]; then
							[[ -n $VERBOSE ]] && echo -n "    `date +%T`: killing child pid '$CHILDPID'"
							kill -- $CHILDPID
							sleep 15s
						fi
						let VSESSIONSTOTAL--
						let VSESSIONSABORTED++
						[[ -n $VERBOSE ]] && echo
						break
					done
				fi
				[[ -n $ALTERNATE ]] && touch "/tmp/$THIS-live-$$.run"
				sleep 10s   # this is not optimal, but you can't use wait here
			done
		fi
		[[ -n $ABORTAT && $(date +%s) -ge $ABORTAT ]] && break
	done
	# wait until all concurrent verify sessions have finished
	[[ -n $ABORTAT && $(date +%s) -ge $ABORTAT ]] && break
	if [ -n "$RDIFFWEBFIX" -a "$THISUSER" = "root" ]; then
		UNAME="`stat -c %U $ORIGD`"
		# now do the rdiffWeb restore.log ownership fix
		if [ -O "$ORIGD/restore.log" ]; then
			# if restore.log exists and is owned by root, change ownership
			echo -en "\nChanging $ORIGD/restore.log to owned by $UNAME"
			chown "$UNAME:" $ORIGD/restore.log && echo ": OK" || echo ": FAILED"
		elif [ ! -f "$ORIGD/restore.log" ]; then
			# create restore.log if not existing and set owner
			echo -en "\nCreating $ORIGD/restore.log as owned by $UNAME"
			touch $ORIGD/restore.log 2>/dev/null && chown "$UNAME:" $ORIGD/restore.log && echo ": OK" || echo ": FAILED"
		else
			ONAME="`stat -c %U $ORIGD/restore.log`"
			if [ "$UNAME" != "$ONAME" ]; then
				echo -en "\nChanging $ORIGD/restore.log to owned by $UNAME instead of $ONAME"
				chown "$UNAME:" $ORIGD/restore.log && echo ": OK" || echo ": FAILED"
			elif [ -n "$VERBOSE" ]; then
				echo -en "\n$ORIGD/restore.log is already owned by $UNAME - no change required"
			fi
		fi
	fi
	REPOERRTOTAL=$(($REPOERR+$REPOERRTOTAL))
	[[ -s "$ORIGD/verified-fake.log" ]] && { rm "$ORIGD/verified-fake.log" || echo "Warning: unable to remove $ORIGD/verified-fake.log" >&2; }
done
unset IFS
[[ -z $DEBUG ]] && { removesnapshot; rm -f "/tmp/$THIS-$$"* "/tmp/$THIS-live-$$.run"; }
if [[ -z $QUIET ]]; then
	echo -en "\n`date +%H:%M:%S` Completed verifications: $VSESSIONSTOTAL actual, $SKIPPEDVSESSIONSTOTAL skipped"
	[[ $PREVFAKEDVSESSIONSTOTAL -ne 0 || $FAKEDVSESSIONSTOTAL -ne 0 ]] && echo -n " (of which $PREVFAKEDVSESSIONSTOTAL were previous fake verifications and $FAKEDVSESSIONSTOTAL were faked on this run)"
	echo ", $VSESSIONSABORTED aborted, $REPOERRTOTAL error(s)"
fi
exit $REPOERRTOTAL
