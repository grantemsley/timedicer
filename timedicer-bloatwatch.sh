#!/bin/bash
VERSION="0.4 [04 Feb 2016]"
BLOATALLOWDEFAULT=256
BLOATED=0
BACKSTEP=1
while getopts ":dhln:psvwz:" optname; do
	case "$optname" in
		"d") DEBUG="y";;
		"h") HELP="y";;
		"l") CHANGELOG="y";;
		"n") BACKSTEP=$OPTARG;;
		"p") USEPREVIOUS="y"; [[ $BACKSTEP -eq 1 ]] && BACKSTEP=2;;
		"s") SAVE="y";;
		"v") VERBOSE="y";;
		"w") COLUMNS="9999";;
		"z") DOLAST="$OPTARG";;
		"?") echo "Unknown option $OPTARG"; exit 1;;
		*) echo "Unknown error while processing options"; exit 1;;
	esac
done
shift $(($OPTIND-1))
THIS=`basename $0`
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }

[ -z "$QUIET" -o -n "$HELP" -o -n "$CHANGELOG" ] && echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -n "$HELP" ]; then
	echo -e "Checks for growth in size of rdiff-backup repositories at \
/home/*/[here] and /home/*/*/[here] since the last time $THIS was run. \
If the growth of any repository is greater in MiB than the value stored \
in the single-line file bloatwatch.daily in that repository's \
rdiff-backup-data subdirectory (default $BLOATALLOWDEFAULT) then a warning \
is shown and the program will exit with code >0.

$THIS is part of the TimeDicer Server software suite.

Usage:\t $THIS [options]

Options:
  -h - show this help and quit
  -l - show changelog and quit
  -n [num] - compare repository sizes with sizes num backups ago (default: 1)
  -p - instead of current repository sizes, bases for comparison are the sizes when $THIS was last run with -s; in this case the default -n option becomes 2
  -s - save results
  -v - verbose output
  -z [name] - process any repositories with path containing text 'name' last

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
0.4 [04 Feb 2016] - improve text output
0.3 [01 Feb 2016] - add -z option
0.2 [26 Jan 2016] - add -s, -p and -n options, change text output
0.1 [13 Jan 2016] - first version
"|fold -sw $COLUMNS
fi
[ -n "$HELP$CHANGELOG" ] && exit 0
[ -n "$DEBUG" ] && echo "Debug mode"



TMPF=$(mktemp)
[[ $(id -u) -eq 0 ]] || { echo "Must run as root or with sudo, sorry"; exit 1; }
[[ -n $VERBOSE ]] && echo -en "All sizes in Mebibytes\nObtaining locations of repositories in /home: "
find /home -mindepth 2 -maxdepth 4 -type d -name rdiff-backup-data|sed 's@/rdiff-backup-data$@@'|sort >$TMPF
[[ -n $DOLAST ]] && sed -i "/${DOLAST//\//\\/}"'/{H;d};${G;s/\n//}' $TMPF
[[ -n $VERBOSE ]] && echo "[OK]"
while read REPO; do
	BFILE="$REPO/rdiff-backup-data/bloatwatch"
	[[ ! -f $BFILE.log ]] && touch $BFILE.log
	LOGLINETOT=$(<$BFILE.log wc -l)
	if [[ -z $USEPREVIOUS ]]; then
		SIZEM=$(du -sBM $REPO|awk -F "M" '{print $1}')
		TIME_S=$(date +%s)
		TIME_H=$(date +"%F %T")
	elif [[ $LOGLINETOT -ge 1 ]]; then
		# feed strings into read with <<<. feed documents with <<, feed commands with < <(...)
		read SIZEM TIME_S TIME_H < <(tail -n1 $BFILE.log)
	else
		SIZEM=0
	fi
	if [[ $LOGLINETOT -ge $BACKSTEP ]]; then
		PREV=( $(tail -n $BACKSTEP "$BFILE.log" | head -n1) )
		GROWTH=$(($SIZEM-${PREV[0]}))
		DAYS=$(( (($TIME_S-${PREV[1]}+10800)/86400) ))
		[[ $DAYS -lt 1 ]] && DAYS=1
		[[ $DAYS -eq 1 ]] && DAYTEXT="day" || DAYTEXT="days"
		BLOATALLOW=$BLOATALLOWDEFAULT
		[[ -s "$BFILE.daily" ]] && BLOATALLOW=$(cat "$BFILE.daily")
		TEXT="$(printf "%+.0f" $GROWTH) in $DAYS $DAYTEXT, $SIZEM total, ${PREV[2]} ${PREV[3]} to $TIME_H - $REPO"
		if [[ $(( $GROWTH/$DAYS )) -gt $BLOATALLOW ]]; then
			echo "$TEXT >${BLOATALLOW}/day:[WARN]"; let BLOATED++
		elif [[ -n $VERBOSE ]]; then
			echo "$TEXT <${BLOATALLOW}/day:[OK]"
		fi
	elif [[ -n $VERBOSE ]]; then
		echo " - no previous bloatwatch entry found: [OK]"
	fi
	[[ -n $SAVE && -z $USEPREVIOUS ]] && echo "$SIZEM $TIME_S $TIME_H" >>"$BFILE.log"
done <$TMPF
[[ -n $DEBUG ]] && echo "Retained temp file $TMPF" || rm $TMPF
[[ $BLOATED -gt 0 || -n $VERBOSE ]] && echo "$BLOATED repositories have grown alarmingly..."
exit $BLOATED
