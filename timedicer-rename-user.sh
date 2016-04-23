#!/bin/bash
VERSION="0.7 [21 Mar 2014]"
THIS=`basename $0`; COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
while getopts "dhrwx" optname; do
    case "$optname" in
		"d")	DEBUG="y";;
		"h")	HELP="y";;
		"r")	RDWONLY="y";;
		"w")	COLUMNS=30000;;
		"x")	DELETE="y";;
		*)	echo "Unknown error while processing options"; exit 1;;
    esac
done
shift $(($OPTIND-1))

echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [ -n "$HELP" ]; then
	echo -e "A simple way to rename or delete a user on a TimeDicer Server. This \
script is useful if a source machine has been reconfigured so that the \
default username (%USERNAME%-%USERDOMAIN%) has changed. It requires that \
[oldname] has a primary group also called [oldname] and a home \
directory at /home/[oldname], and will refuse to run otherwise.

After a warning prompt, it will rename or delete the user, the group and \
the user's home directory. Deleting (but not renaming) a user in this way \
will also irretrievably delete their /home folder - for TimeDicer, this is \
normally their rdiff-backup archive(s) - you have been warned!

If an rdiffWeb database is found, then after a further warning prompt \
sqlite3 is (installed and) used to correct the corresponding entry there.

Usage:    sudo ./$THIS [options] oldname [newname]

Example:  sudo ./$THIS frederick-fredspc fred-freds

Options:  -h show help and exit
          -r only make changes to rdiffWeb database
          -x to delete the user

Dependencies: apt-get awk bash deluser find fold grep groupmod sed sqlite3 stty usermod

License: Copyright 2014 Dominic Raferd. Licensed under the Apache License, \
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
[ "$(id -u)" != "0" ] && echo -e "Sorry, $THIS must be run as root\n">&2 && exit 1
if [ -z "$DELETE" ]; then
	[ -z "$1" -o -z "$2" -o -n "$3" ] && { echo "2 command-line parameters required, please check, aborting...">&2; exit 1; }
else
	[ -z "$1" -o -n "$2" -o -n "$3" ] && { echo "1 command-line parameter required with -d option, aborting...">&2; exit 1; }
fi
if [ -z "$RDWONLY" ]; then
	if [ -z "$DELETE" ]; then
		echo -e "Will try to change username '$1' to '$2'\nChecking:"
	else
		echo -e "Will try to delete user '$1'\nChecking:"
	fi
	grep -n "^$1:" /etc/passwd >/dev/null || { echo "Can't find user '$1' in /etc/passwd, aborting...">&2; exit 1; }
	echo "  Found existing user '$1' - ok"
	#CHECKGROUPNAME=`grep "^$1:" /etc/passwd|awk -F "[:,]" '{print $5}'`
	#[ "$CHECKGROUPNAME" != "$1" ] && { echo "Can't find group '$1' in /etc/passwd, aborting...">&2; exit 1; }
	#echo "  Found existing group '$1' in /etc/passwd - ok"
	CHECKGROUPNAME=`grep "^$1:" /etc/group|awk -F ":" '{print $1}'`
	[ "$CHECKGROUPNAME" != "$1" ] && { echo "Can't find group '$1' in /etc/group, aborting...">&2; exit 1; }
	echo "  Found existing group '$1' in /etc/group - ok"
	CURRENTHOME="`find /home -mindepth 1 -maxdepth 1 -type d -name "$1"`"
	[ -z "$CURRENTHOME" ] && { echo "Can't find home '/home/$1', aborting..."; exit 1; }
	echo "  Found existing home '/home/$1' - ok"
	if [ -z "$DELETE" ]; then
		NEWHOME="`find /home -mindepth 1 -maxdepth 1 -type d -name "$2"`"
		[ -n "$NEWHOME" ] && { echo "Found existing home '/home/$2', aborting..."; exit 1; }
		echo "  No existing home '/home/$2' - ok"
	fi

	read -t 20 -p "Ready to proceed, are you sure (y/-)? "
	[ "$REPLY" != "y" -a "$REPLY" != "Y" ] && { echo "No changes made, aborting..."; exit 0; }

	if [ -z "$DELETE" ]; then
		echo "Changing user from '$1' to '$2'"
		usermod -l "$2" "$1" || { echo "Error $? occurred, aborting..."; exit $?; }
		echo "Changing home directory to '/home/$2/'"
		usermod -m -d /home/"$2" "$2" || { echo "Error $? occurred, aborting..."; exit $?; }
		echo "Changing groupname in /etc/groups from '$1' to '$2'"
		groupmod -n "$2" "$1" || { echo "Error $? occurred, aborting..."; exit $?; }
		echo "Changing user ID info in /etc/passwd from '$1' to '$2'"
		sed -i "/^$2:/{s/:$1,/:$2,/}" /etc/passwd || { echo "Error $? occurred, aborting..."; exit $?; }
		echo "User/group/home changes completed ok"
	else
		hash deluser 2>/dev/null || { echo -e "Sorry, we can only delete a user on a Debian-based distro\nNo changes made, aborting...">&2; exit 1; }
		read -t 20 -p "Delete user $1 and all associated data irretrievably - really sure (y/-)? "
		[ "$REPLY" != "y" -a "$REPLY" != "Y" ] && { echo "No changes made, aborting..."; exit 0; }
		echo "Deleting user '$1', including his/her group and home directory"
		deluser --remove-home "$1" || { echo "Error $? occurred, aborting..."; exit $?; }
	fi
fi

[ ! -s "/etc/rdiffweb/rdw.db" ] && exit 0
hash sqlite3 2>/dev/null
if [ $? -gt 0 ]; then
	hash apt-get 2>/dev/null
	if [ $? -gt 0 ]; then
		echo -e "Unable to install sqlite3 because not a debian-based distro\nTo make changes to rdiffWeb database, install sqlite3 and retry with -r\nNo changes made to rdiffWeb database">&2; exit 1
	else
		apt-get -qq install sqlite3 || { echo -e "A problem occurred trying to install sqlite3\nTo make changes to rdiffWeb database, install sqlite3 and retry with -r\nNo changes made to rdiffWeb database"; exit 1; }
	fi
fi
OLDUSER="$1"
OLDUSERROOT="$(sqlite3 /etc/rdiffweb/rdw.db "SELECT UserRoot FROM users WHERE Username='$OLDUSER';")"
[ -z "$OLDUSERROOT" ] && { echo "User '$1' not found in rdiffWeb database, no update required"; exit 1; }
if [ -z "$DELETE" ]; then
	NEWUSER="$2"
	NEWUSERROOT="$(sqlite3 /etc/rdiffweb/rdw.db "SELECT UserRoot FROM users WHERE Username='$NEWUSER';")"
	[ -n "$NEWUSERROOT" ] && { echo "Unable to update rdiffWeb database, user '$NEWUSER' already exists"; exit 1; }
	NEWUSERROOT=$(echo -n "$OLDUSERROOT"|sed "s@/home/$OLDUSER/@/home/$NEWUSER/@")
	[ -n "$DEBUG" ] && echo "NEWUSERROOT: '$NEWUSERROOT'"
else
	OLDUSERID="$(sqlite3 /etc/rdiffweb/rdw.db "SELECT UserID FROM users WHERE Username='$OLDUSER';")"
fi
read -t 20 -p "Ready to update rdiffWeb database, are you sure (y/-)? "
[ "$REPLY" != "y" -a "$REPLY" != "Y" ] && { echo "No changes made to rdiffWeb database, aborting..."; exit 0; }
if [ -z "$DELETE" ]; then
	sqlite3 /etc/rdiffweb/rdw.db "UPDATE users SET UserRoot='$NEWUSERROOT', Username='$NEWUSER' WHERE Username='$OLDUSER';" && { echo "rdiffWeb database was updated ok"; exit 0; } || { echo "There was a problem updating rdiffWeb database"; exit $?; }
else
	sqlite3 /etc/rdiffweb/rdw.db "DELETE FROM repos WHERE UserID=$OLDUSERID; DELETE FROM users WHERE Username='$OLDUSER';" && { echo "rdiffWeb database was updated ok"; exit 0; } || { echo "There was a problem updating rdiffWeb database"; exit $?; }
fi
