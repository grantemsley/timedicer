#!/bin/bash
VERSION="2.2 [11 Mar 2015]"
THIS=`basename $0`
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }

while getopts ":dhlwx" optname; do
    case "$optname" in
    		"d")	DEBUG="y";;
		"h")	HELP="y";;
		"l")	CHANGELOG="y";;
		"w")	COLUMNS=30000;; #suppress line-breaking
		"x")	DUOPTS="$DUOPTS -x";;
		"?")	echo "Unknown option $OPTARG"; exit 1;;
		":")	echo "No argument value for option $OPTARG"; exit 1;;
		*)	# Should not occur
			echo "Unknown error while processing options"; exit 1;;
    esac
done
shift $(($OPTIND-1))
[ -n "$CHANGELOG$HELP" -o -z "$QUIET" -o -z "$1" ] && echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -n "$HELP" ]; then
	echo -e "GNU/Linux command-line program which shows a tree-style \
list of files and directories at the specified location but only showing \
directories and files greater than a specified size (default 1GB).

The purpose is to identify how storage space is being used and where it \
might be being wasted. $THIS make it easy to focus on the big space hogs.

Usage:        $THIS [options] /mydir/mysubdir [size]
              where (optional) size can be:
                T - for >1TB
                F - for >10GB
                G or missing - for >1GB
                H - for >100MB
                N - for >10MB
                M - for >1MB
                K - for >1KB

Options:      -h - show help and exit
              -l - show changelog and exit
              -x - ignore files/directories in a different filesystem

Example Output: You can see an example of ${THIS}'s output at http://www.timedicer.co.uk/dutree.jpg

Dependencies: awk, basename, bash, du, fold, grep, sort, stty

License: Copyright 2015 Dominic Raferd. Licensed under the Apache License, \
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
	[ -n "$HELP" ] && echo "Changelog:"
	echo -e "\
2.2 [11 Mar 2015] - bugfix deletion of temporary files
2.1 [28 Dec 2014] - bugfix for names containing %
2.0 [28 Oct 2014] - improved layout
1.9 [14 Oct 2014] - add -x option
1.8 [03 Apr 2014] - use /tmp instead of /var/tmp
1.7 [01 Nov 2013] - exclude /proc
1.6 [07 Nov 2012] - fix layout if location does not start with slash
1.5 [14 Aug 2012] - add F option for >10GB
1.4 [13 Aug 2012] - show help if no location is specified
1.3 [24 Jul 2012] - bugfix - prevent abort message if no files big enough found
1.2 [30 May 2012] - bugfix - was broken when run w/o specifying a size parameter, also added a link in help text to some example output
1.1 [02 May 2012] - add more options, add help/changelog, directories now shown with trailing slash
1.0 [01 May 2012] - initial releasek
"|fold -s -w $COLUMNS
fi
[ -n "$CHANGELOG$HELP" -o -z "$1" ] && exit 0
TEMP="/tmp"
SIZES="GT"
NEGATIVEFILTER="^zzz"
if [ "$2" = "M" -o "$2" = "N" -o "$2" = "H" ]; then
	SIZES="MGT"
	[ "$2" = "N" ] && NEGATIVEFILTER="^[0-9](\.[0-9])?M"
	[ "$2" = "H" ] && NEGATIVEFILTER="^([1-9])?[0-9](\.[0-9])?M"
elif [ "$2" = "F" ]; then
	NEGATIVEFILTER="^[0-9](\.[0-9])?G"
elif [ "$2" = "K" ]; then
	SIZES="KMGT"
elif [ -n "$2" ]; then
	SIZES="$2"
fi
[ ! -d "$1" ] && echo "$1 is not a directory, aborting">&2 && exit 1
BASESLASHNUM=$(echo $1|awk -F/ '{printf NF}')
[ -n "$DEBUG" ] && echo "BASESLASHNUM: '$BASESLASHNUM'"

du --exclude=/proc/* -ah $DUOPTS "$1" >"$TEMP/$THIS.tmp3"
if [ ! -s "$TEMP/$THIS.tmp3" ]; then
	echo "Unable to search $1, aborting">&2
	EXITCODE=1
else
	grep -E "^[1-9][0-9.]*[${SIZES}]" "$TEMP/$THIS.tmp3"|sort -b -k 2 >"$TEMP/$THIS.tmp1"
	rm -f "$TEMP/$THIS.tmp2"
	while read SIZE ITEM; do
		[ -d "$ITEM" -a "$ITEM" != "/" ] && ENDSLASH="/" || ENDSLASH=""
		echo -e "$SIZE\t$ITEM$ENDSLASH">>"$TEMP/$THIS.tmp2"
	done<"$TEMP/$THIS.tmp1"
	if [ -s "$TEMP/$THIS.tmp2" ]; then
		awk -F "\t|/" -v BASESLASHNUM=$BASESLASHNUM '{printf $1 "\t"; x=1; LAST=(NF-BASESLASHNUM-1-($NF=="")-($2 != "")); while (x<=LAST) {printf "  ";x++}; if ($2 != "") printf "%s",$2; x=3; while (x<=NF) {printf "%s","/" $x; x++} print ""}' "$TEMP/$THIS.tmp2"|grep -Ev "$NEGATIVEFILTER"
	else
		echo "No matching files found"
	fi
	EXITCODE=0
fi
[ -z "$DEBUG" ] && find "$TEMP" -name "$THIS.tmp*" -delete
exit $EXITCODE
