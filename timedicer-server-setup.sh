#!/bin/bash
VERSION="6.0422 [22 Apr 2016]"
# Script to setup initial configuration for TimeDicer Server
#
# For code to download and run this file see end of the file
#
function updateme() {
# parameter0 is the location of the alternative version of this program
# Copies a different version of the script over the current running
# script (which is presumed to be in /opt) so that it can continue with
# the new script.It is critical that in the new version the actual
# line of the new run is still line 25.
	[ -n "$DEBUG" ] && echo "Starting 'updateme'"
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	[ -n "$DEBUG" ] && echo "SOURCE '$SOURCE', DIR '$DIR'"
	if [ ! -x "$1/$THIS" -o ! "$1/$THIS" -nt "$DIR/$THIS" ]; then
		[ -n "$DEBUG" ] && echo "Could not find executable $1/$THIS, or $1/$THIS not newer than $DIR/$THIS, updating of running $THIS skipped"
		return
	fi
	echo -e "Updated $THIS. Please run $THIS again with same parameters as last time."
	cp "/tmp/$THIS" "$DIR"
	exit 0


	exit 0


	exit 0
}
function docmd() {
# call this as e.g. docmd "description of command" "the command to run" "/etc/crontab" "y"
# 3rd parameter if present is the file to append output to
# if 4th parameter is present this acts as force
if [ -n "$4" ]; then
	echo $1; $CURS_UP
	YESNO=$4
elif [ -n "$FORCE" ]; then
	echo $1; $CURS_UP
	YESNO=y;
else
	read -p "${1} (y/-): " YESNO
	$CURS_UP
fi
erred=$?
if [ "$YESNO" = "y" ]; then
	if [ -n "$VERBOSE" ]; then
		echo
		#echo $2
		if [ -n "$3" ]; then
			$2>>"$3"
		else
			$2
		fi
		erred=$?
		#echo -n $1
	else
		if [ -n "$3" ]; then
			$2>>"$3"
		else
			$2>/dev/null
		fi
		erred=$?
	fi
	echo -n $1
	$SET_COL
	if [ "$erred" -eq 0 ]; then
		echo "[ OK ]"
	else
		echo "[FAIL]"
	fi
else
	$SET_COL
	echo "[SKIP]"
	SKIPPED=Y
fi
ERREDTOTAL=$(($ERREDTOTAL+$erred))
return $erred
}
THIS=`basename $0`;echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
COL=$[ $COLUMNS - 5 ]
SET_COL="echo -en \\033[${COL}G"
CURS_UP="echo -en \\033[A"
ERREDTOTAL=0
PRIMARYUSER=`grep :1000: /etc/passwd|awk -F : '{print $1}'`
IPADDRESSES=`ifconfig 2>/dev/null|sed -n '/inet addr:/{s/.*inet addr:\([^ ]*\).*/\1/;/127\.0\.0\.1/d;p}'`
while getopts ":cdflhvw" optname; do
    case "$optname" in
	"c")
		[ "$IPADDRESSES" != "192.168.100.135" ] && echo "Unknown option -c" && exit 1
		# undocumented -c option
		[ `id -u` -ne 0 ] && echo "$THIS must be run with sudo or as root" && exit 1
		set -e # stop on any error
		THISN="$(basename $0 .sh)"
		cp -au /opt/$THIS /tmp/$THIS
		#if [[ ! -s /usr/local/bin/rdiff-web-config ]]; then
		#	[[ -s /opt/rdiff-web-config ]] || { echo "Unable to find /opt/rdiff-web-config, this file was part of rdiffweb 0.6.3, aborting" >&2; exit 1; }
		#	cp -a /opt/rdiff-web-config /usr/local/bin
		#fi
		echo "Obtaining existing files from server"
		mkdir -p /tmp/server
		rsync -c "root@192.168.100.194:/home/z-shares/www/timedicer/htdocs/server/$THISN.*" /tmp/server 2>/dev/null || { echo "Error $?, aborting" >&2; exit 1; }
		echo "Recreating archive file timedicer-setup-server.tar.bz2"
		tar -cjPf /tmp/$THISN.tar.bz2 /opt/timedicer-rename-user.sh /opt/lvm-usage.sh /opt/newuser-request.sh /opt/timedicer-mirror.sh /var/www/html/processing.php /var/www/html/index.php /var/www/html/timedicer-username.bat /var/www/html/timedice.css /var/www/html/timedicer_die.png /var/www/html/timedicer_full.png /var/www/html/favicon.ico /var/www/html/robots.txt /opt/crontab-update.sh /opt/rdiffweb-install.sh /opt/make-home-lv.sh /opt/timedicer-verify.sh /opt/lvm-delete-snapshot.sh /opt/dutree.sh /opt/timedicer-bloatwatch.sh /opt/rdiffweb-adduser.py /tmp/$THIS
		for EXT in sh tar.bz2; do
			diff -q /tmp/server/$THISN.$EXT /tmp/$THISN.$EXT && echo "$THISN.$EXT has not changed, server does not need to be updated" || { echo "Updating $THISN.$EXT on server"; rsync -c /tmp/$THISN.$EXT root@192.168.100.194:/home/z-shares/www/timedicer/htdocs/server/ 2>/dev/null; }
			rm /tmp/server/$THISN.$EXT /tmp/$THISN.$EXT
		done
		rmdir /tmp/server
		ssh root@192.168.100.194 chown timedicer: /home/z-shares/www/timedicer/htdocs/server/timedicer-server-setup.* 2>/dev/null
		echo -e "Successfully verified server $THISN.tar.bz2 and $THISN.sh"
		exit $?;;
 	"d") DEBUG="-d ";;
	"f") FORCE="-f ";;
	"h") HELP=y;;
	"l") CHANGELOG=y;;
	"v") VERBOSE="-v ";;
	"w") COLUMNS=30000;;
	"?") echo "Unknown option $OPTARG"; exit 1;;
	":") echo "No argument value for option $OPTARG"; exit 1;;
	*)
		# Should not occur
		echo "Unknown error while processing options"; exit 1;;
    esac
done
shift $(($OPTIND-1))
if [ "$HELP" = "y" ]; then
	echo -e "$THIS is part of the TimeDicer suite http://www.timedicer.co.uk, and sets up a TimeDicer Server or updates the existing setup.

It is normally run with -f option after the first boot of a new TimeDicer Server machine. It can be run subsequently with or without -f option to update the machine.

Usage: $THIS [option] [you@your_email_address.org]

Options: -v verbose (show normal output from commands)
         -f run automatically assuming 'y' for all questions - email address on command line required
         -h show this help
         -l show changelog

Details: Depending on the user's choices and existing installed software, \
the server is configured as follows -
- download and extract key scripts from www.timedicer.co.uk (including \
self-updating this script)
- check and update timezone information [requires user response]
- download and install postfix [requires user response]
- download and install updates for Ubuntu
- restrict access to users' /home folders to the respective user
- download and install sshfs and add new users automatically to FUSE group
- download and install wakeonlan, lvm2, ssh, apache2, php5
- bespoke settings for nano, php, postfix, cron, and enable apache2.conf
- create ssh keys for primary user and for root
- download and install rdiff-backup and rdiffweb
- start rdiffweb, apache2 and postfix
- send a test email

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
	[ -n "$HELP" ] && echo -n "Changelog: "
	echo "[version indicates when: 201y.mmdd]
6.0422:  internal changes
6.0218:  no longer compulsory to supply email address on command line (except with -f)
5.1224:  install new rdiff-backup >=0.7
5.0806:  some bugfixes
5.0129:  add dutree.sh
4.1203:  bugfix so that local TimeDicer homepage appears correctly after installation
4.1116:  further small changes for Ubuntu 14.04
4.1111:  fix for Ubuntu 14.04 (copy web page files to /var/www/html)
2.1107:  timedicer-mirror.sh updated
2.0827:  timedicer-mirror.sh updated, help text updated
2.0701:  fix for Ubuntu 12.04 to prevent apache2 messages about undefined ServerName
2.0627:  fix for Ubuntu 12.04 to allow creation of primary user rsa key, \
don't create /home/tmp, add cryptsetup package to prevent inotify_add_watch \
messages/delay at boot time
2.0515:  renamed as $THIS, now self-updating
2.0425:  fix of a small (but fatal) bug
2.0312:  small bugfix, updated help text for rdiffweb-install.sh
2.0308:  rename timedicer-mirror as timedicer-mirror.sh
2.0224:  remove rdiff-backup-fs-install and vmware-tools-install from \
package of installed utilities, rename rdiffweb-install as rdiffweb-install.sh
2.0221:  rename lv-usage.sh as lvm-usage.sh
1.1231:  improved output from lv-usage.sh (cron job test for disk space)
1.1023:  create /home/tmp directory when rdiff-backup is installed
1.1011:  recoding for timedicer-mirror
1.1009:  bugfixes for rdiffweb-install, timedicer-mirror and newuser-request.sh
1.0916a: remove heirloom-mailx (and remove dependency upon it)
1.0916:  add timezone configuration
1.0915c: fix rdiffweb-install failure on 2nd run, add rdiffweb setup package \
to timedicer-server-setup.tar.bz2 so setup can still work if rdiffweb site is down
1.0915:  add recognition of any type of network port
1.0914:  add make-home-lv.sh, can ease LVM configuration \
fix for rdiffweb-install to work with python2.7 (Ubuntu 11.04)
1.0913:  add install of postfix, lvm2, ssh and heirloom-mailx to assist with \
VM-based or non-standard TimeDicer Server setup
1.0901:  alter Server web pages so no data (css, png) is loaded from \
www.timedicer.co.uk, all is held and accessed locally - removes \
an unintended 'phone home' and means page formats are okay even \
if Server has no internet access
1.0830:  alter various files so that when a new TimeDicer user is created, a new \
rdiffweb user is also created
1.0306:  remove installation of rdiff-backup-fv [patched rdiff-backup]
1.0301:  bugfix - prevent automatic silent abort on exit code>0 \
remove daily repo verification from cron
1.0227:	 added changelog option and updated help text
1.0222:  install wakeonlan, add script install-rdiff-backup-fs \
(but rdiff-backup-fs not installed)
1.0217:  install sshfs and auto-add new users to fuse group
1.0216:  bugfix - create root rsa key without passphrase
1.0207:  bugfixes
"
fi
[ -n "$HELP$CHANGELOG" ] && exit 0

[ `id -u` -ne 0 ] && echo "$THIS must be run with sudo or as root" && exit 1

[ -n "`echo $1|grep .*@.*`" ] && MYEMAIL="$1"

[[ -n $FORCE && -z $MYEMAIL ]] && { echo "Missing parameter: please rerun, specifying an email address to receive notices from TimeDicer Server"; exit 1; }

[ -z "$IPADDRESSES" ] && echo "Unable to find ip address from this machine, aborting..." && exit 1

docmd "Download and extract key scripts from www.timedicer.co.uk" "wget -qO /tmp/timedicer-server-setup.tar.bz2  http://www.timedicer.co.uk/server/timedicer-server-setup.tar.bz2"
TOWEBDIR="/var/www/html"
if [ "$YESNO" = "y" ]; then
	[ ! -e /tmp/timedicer-server-setup.tar.bz2 ] && { echo "Sorry, couldn't find downloaded key scripts, unable to continue"; exit 1; }
	if [ "$IPADDRESSES" != "192.168.100.134" ]; then
		tar --overwrite --preserve-permissions --no-overwrite-dir -xPjf /tmp/timedicer-server-setup.tar.bz2
		if [ $? -ne 0 ]; then echo "Error extracting: unable to continue"; exit 1; fi
	fi
	# code to run a newer version of this program if one was extracted (to /tmp)
	if [ -n "`diff -q "/opt/$THIS" "/tmp/$THIS"`" ]; then
		updateme /tmp
	fi
	# create subfolder for newuser details
	mkdir -p /var/www/.adduser
	chmod 777 /var/www/.adduser
	# set permissions of batch file so it can be accessed
	chmod 644 "/var/www/html/timedicer-username.bat"
	if [[ -d /etc/apache2/sites-enabled ]]; then
		TOWEBDIR=$(grep -R "DocumentRoot\s*/var/www" /etc/apache2/sites-enabled|awk '{print $NF; exit}')
		# move web pages from /var/www/html
		# normally has no effect, but if running on a machine which does not have its document root at
		# /var/www/html (e.g. Ubuntu 12.04) then should allow TimeDicer local webpage to work
		[ "$TOWEBDIR" != "/var/www/html" ] && find /var/www/html -maxdepth 1 -type f|xargs -I {} mv {} "$TOWEBDIR"
	fi
fi

# a few things at the beginning are interactive, so VERBOSE must be on
VERBOSE_HOLDER=$VERBOSE; VERBOSE="-v "
# check timezone
docmd "Check/update timezone information" "dpkg-reconfigure tzdata"
# install postfix
[ ! -f "/etc/mailname" ] && docmd "(Re)install & configure postfix" "apt-get -qqy install postfix"
VERBOSE=$VERBOSE_HOLDER
[ -n "$DEBUG" ] && echo "passed postfix installation"

# update distro to latest
DISTRO=`lsb_release -ds`
docmd "Download and install latest updates for $DISTRO" "apt-get update -y"
[ $? -eq 0 -a "$YESNO" = "y" ] && docmd "Installing $DISTRO updates - may take some time" "apt-get upgrade -y --force-yes" "" "y"

# so new users home folders are readable/writeable only by themselves
if [ "`egrep -c DIR_MODE=0700 /etc/adduser.conf`" -eq 0 ]; then
	docmd "Set home folders to be inaccessible to others" "sed -i s/DIR_MODE=0755/DIR_MODE=0700/ /etc/adduser.conf"
	if [ "$YESNO" = "y" ]; then chmod -R 0700 /home/$PRIMARYUSER; fi
fi
if [ -z `grep "^EXTRA_GROUPS" /etc/adduser.conf` ]; then
	docmd "Install sshfs, and add new users automatically to FUSE group" "echo -n"
	if [ "$YESNO" = "y" ]; then
		apt-get install -yqq sshfs
		echo -e "EXTRA_GROUPS=\"fuse\"\nADD_EXTRA_GROUPS=1">>/etc/adduser.conf
	fi
fi

# set some friendly default options for nano for primary user
if [ "`egrep -c \"^set softwrap\" /etc/nanorc`" -eq 0 ]; then
	docmd "Set nice default options for nano text editor" "echo -e set softwrap\\nset const\\nset morespace\\nset noconvert" "/etc/nanorc"
	if [ "$YESNO" = "y" ]; then
		touch /home/$PRIMARYUSER/.nano_history
		chown $PRIMARYUSER: /home/$PRIMARYUSER/.nano_history
	fi
fi

# install wakeonlan
if [ `whereis wakeonlan 2>/dev/null|wc -w` -lt 2 ]; then
	docmd "Install wakeonlan (needed for timedicer-mirror.sh)" "apt-get -q install wakeonlan"
fi

# install postfix, lvm2, ssh, apache2, and php5 [- also cryptsetup (to stop inotify_add_watch error messages at boot)]
docmd "(Re)install & configure lvm2 ssh apache2 php5" "apt-get -qq install lvm2 ssh apache2 php5"
if [ "$YESNO" = "y" ]; then
	# alter timeout setting so it is long enough for user creation
	sed -i 's/max_execution_time = 30/max_execution_time = 180/' /etc/php5/apache2/php.ini
	sed -i 's/max_input_time = 30/max_input_time = 180/' /etc/php5/apache2/php.ini
	# move the default apache homepage so that index.php will be used instead
	[ -f $TOWEBDIR/index.html ] && mv -f $TOWEBDIR/index.html $TOWEBDIR/index.old
	# if ServerName directive missing from apache2.conf, add it
	if [ `egrep -c "^ServerName " /etc/apache2/apache2.conf` -eq 0 ]; then
		sed -i 's/^#\{0,1\}\(ServerRoot .*\)/\1\n# ServerName added by timedicer-server-setup\nServerName localhost/' /etc/apache2/apache2.conf
	fi
	apache2ctl -k graceful
fi
[ -n "$DEBUG" ] && echo "passed php/apache etc installation"

# alter postfix settings so that emails to the same domain as this machine
# (as set at setup time) do not loop back to here
MAILDOMAIN=`cat /etc/mailname 2>/dev/null`
if [ -n "$MAILDOMAIN" ]; then
	docmd "Configure email settings (postfix)" "echo -n"
	if [ "$YESNO" = "y" ]; then
		[[ -z $MYEMAIL ]] && { echo "Unable to continue: please rerun, specifying an email address to receive notices from TimeDicer Server"; exit 1; }
		sed -i  "s/\(^\s*mydestination = \s*\)$MAILDOMAIN,\s*\(.*\)/\1\2/" /etc/postfix/main.cf
		# alteration so that emails back to 'root' or 'postmaster' go out to the user
		echo -e "# see man 5 aliases for further info\n# modified by $THIS `date`\npostmaster: $1\nroot: $1">/etc/aliases
		newaliases
		# alteration so that emails from 'root' or 'postmaster' appear to be from '(machinename)'
		echo -e "# modified by $THIS `date`\nroot `uname -n`\npostmaster `uname -n`">/etc/postfix/generic
		if [ `egrep -c "^smtp_generic_maps" /etc/postfix/main.cf` -gt 0 ]; then
			sed -i 's@^\(smtp_generic_maps\).*@\1 = hash:/etc/postfix/generic@' /etc/postfix/main.cf
		else
			echo "smtp_generic_maps = hash:/etc/postfix/generic">>/etc/postfix/main.cf
		fi
		postmap /etc/postfix/generic
		# reload postfix with changes
		postfix reload 2>/dev/null
	fi
fi

# establish primary user key, there will be problems with ssh-keygen if primaryuser name has a space in it!
if [ -z "`ls /home/\"$PRIMARYUSER\"/.ssh/id_rsa 2>&-`" ]; then
	# create and set permissions and ownership for .ssh folder (rqd for Ubuntu 12.04)
	mkdir -p -m 700 /home/"$PRIMARYUSER"/.ssh && chown "$PRIMARYUSER":$(id -gn "$PRIMARYUSER") /home/"$PRIMARYUSER"/.ssh
	# we have to set a real passphrase here, trying to set blank does not work
	docmd "Setup user '$PRIMARYUSER' private/public key" "ssh-keygen -q -f /home/$PRIMARYUSER/.ssh/id_rsa -C autocreated-by-timedicer-server-setup-for-$PRIMARYUSER@`uname -n` -N passphrase"
	# now we can change passphrase to blank as direct command
	[ "$YESNO" = "y" ] && ssh-keygen -q -f /home/"$PRIMARYUSER"/.ssh/id_rsa -p -P passphrase -N ''>/dev/null 2>&1
	chown -R "$PRIMARYUSER":"$PRIMARYUSER" /home/"$PRIMARYUSER"/.ssh
fi
[ -n "$DEBUG" ] && echo "passed '$PRIMARYUSER' key install"

# establish root key
if [ -z "`ls /root/.ssh/id_rsa 2>&-`" ]; then
	# we have to set a real passphrase here, trying to set blank does not work
	docmd "Setup root private/public key (for mirroring)" "ssh-keygen -q -f /root/.ssh/id_rsa -C autocreated-by-timedicer-server-setup-for-root@`uname -n` -N passphrase"
	# now we can change passphrase to blank as direct command
	[ "$YESNO" = "y" ] && ssh-keygen -q -f /root/.ssh/id_rsa -p -P passphrase -N ''>/dev/null 2>&1
fi
[ -n "$DEBUG" ] && echo "passed root key install"

# install rdiff-backup
docmd "Install rdiff-backup" "echo -n"
if [ "$YESNO" = "y" ]; then
	apt-get install -qq rdiff-backup
	[ -n "$DEBUG" ] && echo "passed rdiff-backup installation"
fi

# install rdiffweb
docmd "Install rdiffweb" "/opt/rdiffweb-install.sh -y"
[ -n "$DEBUG" ] && echo "passed rdiffweb installation"
if [[ -s /etc/rdiffweb/rdw.conf ]]; then
	# a little custom configuration of the rdiffweb webpage
	grep "^FavIcon=" /etc/rdiffweb/rdw.conf >/dev/null || echo -e "FavIcon=/var/www/html/favicon.ico\nHeaderLogo=/var/www/html/timedicer_die.png\nHeaderName=rdiffweb on TimeDicer Server" >>/etc/rdiffweb/rdw.conf
	service rdiffweb restart
fi

# install options to crontab
[[ -z $MYEMAIL ]] && { echo "Unable to continue (update crontab, send test email): please rerun, specifying an email address to receive notices from TimeDicer Server"; exit 1; }
docmd "Install/Update options to crontab" "/opt/crontab-update.sh $1"

docmd "Send test email to $1" "echo -n"
[ "$YESNO" = "y" ] && MAILMESSAGE=y
MAILTAIL="\n\nDo not reply to this email, you will not receive a response.\n\nThank you for using TimeDicer."

if [ "$ERREDTOTAL" -eq 0 -a -n "$FORCE" ]; then
	MESSAGE="\nTimeDicer Server '`uname -n`' has been successfully configured. You can now access your TimeDicer Server from a browser on the same network at:\n"
	for i in "$IPADDRESSES"; do
		MESSAGE="${MESSAGE}http://$i\t\t(to add users)\nhttp://$i:8080\t(rdiffweb - for recovering files)"
	done
	echo -e $MESSAGE|fold -s -w $COLUMNS
	[ -n "$MAILMESSAGE" ] && echo -e "Subject: TimeDicer Server `uname -n` at $IPADDRESSES: Successful Configuration\n\n$MESSAGE$MAILTAIL"|sendmail $1
else
	[ -n "$MAILMESSAGE" ] && echo -e "Subject: TimeDicer Server at $IPADDRESSES: Test email\n\nThis email was sent by $THIS and if you received it, your TimeDicer Server `uname -n` at $IPADDRESSES can now send emails to you.$MAILTAIL"|sendmail $1
fi
exit 0
# example code to run this script with questions (alter my@emailaddress first):
cd /opt
sudo wget http://www.timedicer.co.uk/server/timedicer-server-setup.sh
sudo chmod 744 timedicer-server-setup.sh
sudo /opt/timedicer-server-setup.sh my@emailaddress

# example code to run this script without questions (alter my@emailaddress first):
cd /opt
sudo wget http://www.timedicer.co.uk/server/timedicer-server-setup.sh
sudo chmod 744 timedicer-server-setup.sh
sudo /opt/timedicer-server-setup.sh -f my@emailaddress
