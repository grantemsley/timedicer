#!/bin/bash
VERSION="3.04 [19 Feb 2016]"
BRANCH="master"
#DEBUG=y
set -o pipefail
# Script by Dominic Raferd to install rdiffweb:
# Any pre-existing rdiffweb configuration is retained, unless -f option is given

[ "`echo -e ""`" != "" ] && echo "Sorry, this must be run using bash shell.">&2 && exit 1
THIS=`basename $0`
COLUMNS=$(stty size 2>/dev/null||echo 80); COLUMNS=${COLUMNS##* }
while getopts ":dfhlwy" optname; do
    case "$optname" in
		"d")	BRANCH="develop";;
		"f")	FORCE=y;;
		"h")	HELP=y;;
		"l")	CHANGELOG=y;;
		"w")	COLUMNS=30000;; #suppress line-breaking
		"y")	NOPROMPT=y;;
		"?")	echo "Unknown option $OPTARG">&2; exit 1;;
		":")	echo "No argument value for option $OPTARG">&2; exit 1;;
		*)	# Should not occur
			echo "Unknown error processing options">&2; exit 1;;
    esac
done
shift $(($OPTIND-1))

echo -e "\n$THIS v$VERSION by Dominic (try -h for help)\n${THIS//?/=}\n"
if [[ -n $HELP ]]; then echo -e "rdiffweb, available from \
http://www.patrikdufresne.com/en/rdiffweb, is a web interface for browsing \
and restoring from rdiff-backup repositories. $THIS downloads, builds, installs, \
configures and tests rdiffweb together with all dependencies.

If updating an existing installation (including v0.6.3 and earlier), any \
settings are retained. Use \
option -f to 'clean' an existing installation and restore settings to defaults.

Normally it installs the latest master version, however with option \
-d it will install the latest development version.

$THIS has been tested under Ubuntu 14.04 and 15.10 but should work under \
any distro. For Debian-based distros it uses apt-get to ensure all \
rdiffweb's dependencies are met, for other distros you must do this yourself \
(sorry). (Note: the dependencies listed below are for this install program, not \
for rdiffweb itself.)


Options: -d install latest development version (instead of master version)
         -f delete any prior rdiffweb configuration
         -h show this help and exit
         -l show changelog and exit
         -y run without prompting

Dependencies: [apt-get] bash coreutils grep ps python2 sed tar wget

License: Copyright 2016 Dominic Raferd. Licensed under the Apache License, \
Version 2.0 (the \"License\"); you may not use this file except in compliance \
with the License. You may obtain a copy of the License at \
http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable \
law or agreed to in writing, software distributed under the License is \
distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY \
KIND, either express or implied. See the License for the specific language \
governing permissions and limitations under the License.\n"|fold -s -w $COLUMNS
fi
if [[ -n $CHANGELOG ]]; then
	echo -e "\
3.04 [19 Feb 2016] - remove non-critical error message for non-systemd-based OS
3.03 [30 Jan 2016] - fix for systemd-based OS
3.02 [30 Dec 2015] - updated help, allow to be used by non-Debian OS
3.01 [26 Dec 2015] - fix for systemd-based OS
3.00 [24 Dec 2015] - first version to install rdiffweb v0.7 and greater, many changes
2.55 [22 Feb 2015] - updated help information
2.54 [24 Dec 2014] - change download link
2.53 [02 Apr 2014] - use /tmp instead of /var/tmp
2.52 [23 Jan 2014] - updated help and intro text, some code tidied
2.51 [18 Dec 2013] - updated help text
2.50 [23 Oct 2013] - add option to install Patrik Dufresne's updated rdiffweb
2.42 [24 May 2012] - update static wiki link in help
2.41 [22 May 2012] - use alternate download location for rdiffweb if www.rdiffweb.org fails
2.40 [21 May 2012] - add links to help information
2.30 [17 May 2012] - bugfix for locating db_sqlite.py
2.20 [19 Mar 2012] - bugfix (options -f and -y were not working)
2.10 [13 Mar 2012] - now also works under non-Debian distros, add -l changelog option
2.02 [12 Mar 2012] - improve the help text
2.01 [05 Jan 2012] - minor change
1.1031 - add -h (help) option, add license text
1.1012 - further bug fix for fix of db_sqlite.py
1.1009 - fix bug: was failing to untar local copy of rdiffweb installer
1.0915c - use existing install package file if we already have it
1.0915b - fix sed operation which broke rdiffweb if this was run twice
1.0915 - use 1st IP of any network device (not just eth), allow Python2.7
1.0828 - fix db_sqlite.py to prevent deprecation message
1.0818 - remove temporary file from /var/tmp after using it
0.1215a - long-standing version\n"|fold -sw $COLUMNS
fi
[[ -n $CHANGELOG$HELP ]] && exit 0

[ `id -u` -eq 0 ] || { echo "$THIS must be run as root or with sudo">&2; exit 1; }

echo -e "This program will (re-)install rdiffweb."
if [ -f "/etc/rdiffweb/rdw.db" ]; then
	if [ -n "$FORCE" ]; then
		echo "** -f option selected: pre-existing rdiffweb configuration will be deleted! **"
	else
		echo "Note: pre-existing rdiffweb configuration will be retained"
	fi
else
	echo "Note: rdiffweb is not already installed: this will be a new installation"
fi

# Obtain 1st non-local ip (to be shown for rdiffweb page)
MYIP="$(hostname -I|cut -d" " -f1)"; [ -z "$MYIP" ] && MYIP=127.0.0.1

# Download, build & install rdiffweb
echo "Downloading and extracting rdiffweb-$BRANCH"
cd /usr/src
wget -q --no-check-certificate -O- https://github.com/ikus060/rdiffweb/archive/$BRANCH.tar.gz|tar -zx || { echo "An error occurred obtaining/extracting rdiffweb-$BRANCH, aborting..." >&2; exit 5; }
cd "rdiffweb-$BRANCH" || { echo "Could not switch to /usr/src/rdiffweb-$BRANCH directory, aborting... " >&2; exit 6; }
# pre-installation we obtain version number from setup.py
RDWVER=$(sed -n "/version=/{s/.*version='//;s/'.*//;p;q}" setup.py)
[[ -n $RDWVER ]] || { echo "The version number of downloaded rdiffweb could not be determined, aborting..." >&2; exit 6; }

# find if rdiffweb already installed and if so which ver
[[ -s /usr/local/bin/rdiffweb ]] && EXISTINGVER=$(sed -n "/rdiffweb==/{s/.*rdiffweb==//;s/'.*//;p;q}" /usr/local/bin/rdiffweb)
[[ -z $EXISTINGVER && -s /etc/init.d/rdiff-web ]] && EXISTINGVER=0.6.3

echo
[[ -n $EXISTINGVER ]] && echo "Note: rdiffweb v$EXISTINGVER is already installed!"
echo "About to install rdiffweb v$RDWVER"
if [ -z "$NOPROMPT" ]; then
	read -t 60 -p "Do you wish to continue (y/-)? "
	if [[ $REPLY != "y" && $REPLY != "Y" ]]; then
		cd /usr/src; rm -rf /usr/src/rdiffweb-$BRANCH
		echo "User abort, no changes made"
		exit 0
	fi
fi

# Download and install dependencies
command apt-get >/dev/null 2>&1
if [ $? -gt 0 ]; then
	read -t 20 -p "Unable to check dependencies, are you sure you want to continue (y/-)? "
	[[ $REPLY == "y" ]] || { echo "Aborted, no changes made"; exit 0; }
else
	echo "Checking and, if required, downloading and installing dependencies"
	apt-get -qq install python python-cherrypy3 python-pysqlite2 libsqlite3-dev python-jinja2 python-setuptools python-babel rdiff-backup || { echo "An error occurred installing dependencies, aborting...">&2; exit 3; }
fi
[[ ! -d /etc/rdiffweb ]] && echo "Creating /etc/rdiffweb directory" && mkdir -m 755 /etc/rdiffweb

echo "Building rdiffweb v$RDWVER"
python setup.py build >/dev/null || { echo "An error occurred building $BRANCH, aborting..." >&2; exit 6; }

# Stop rdiffweb if already installed and running (cope with versions <0.6.3 and >0.6.3)
for PROCESS in rdiffweb rdiff-web; do
	ps -C $PROCESS >/dev/null && { PROCESSES="$PROCESSES $PROCESS"; /etc/init.d/$PROCESS stop || { echo "An error occurred stopping rdiffweb, aborting...">&2; exit 2; } }
done

echo "Installing rdiffweb v$RDWVER"
python setup.py install >/dev/null || echo "Install ended with exit code $?, but continuing anyway..."
# install may end with error code 1 even though all is okay!
[[ -n $DEBUG ]] && echo "got here 10"
# post-installation we obtain version number from /usr/local/bin/rdiffweb
INSTALLEDVER=$(sed -n "/rdiffweb==/{s/.*rdiffweb==//;s/'.*//;p;q}" /usr/local/bin/rdiffweb)
[[ -n $DEBUG ]] && echo "got here 12"
[[ $INSTALLEDVER == $RDWVER ]] || { echo "Could not verify that we have installed the correct version ('$INSTALLEDVER' vs. '$RDWVER'), aborting..." >&2; exit 6; }
[[ -n $DEBUG ]] && echo "got here 15"

# a few extra things may need doing
# startup for upstart
cp -au extras/init/rdiffweb /etc/init.d || { echo "An error occurred copying rdiffweb to /etc/init.d, aborting..." >&2; exit 6; }
# startup for systemd
if [[ -d /lib/systemd/system ]]; then
	command systemctl >/dev/null 2>&1 && { cp -au extras/systemd/rdiffweb.service /lib/systemd/system/; systemctl --system -f enable rdiffweb; }
#		echo -e "[Unit]\nDescription=rdiffweb Server\nDocumentation=http://www.patrikdufresne.com/en/rdiffweb/\nAfter=network.target\n\n[Service]\nExecStart=/usr/local/bin/rdiffweb --log-access-file=/var/log/rdiffweb-access.log\n\n[Install]\nWantedBy=multi-user.target" >/lib/systemd/system/rdiffweb.service
fi



if [ ! -f "/etc/rdiffweb/rdw.db" -o -n "$FORCE" ]; then
	cp -a rdw.conf /etc/rdiffweb || { echo "An error occurred copying rdw.conf to /etc/rdiffweb, aborting..." >&2; exit 6; }
	chown root:root /etc/rdiffweb/rdw.conf
	chmod 644 /etc/rdiffweb/rdw.conf
	[[ -s /etc/rdiffweb/rdw.db ]] && echo "rdiffweb v$RDWVER will have clean configuration" && rm /etc/rdiffweb/rdw.db
	RDWCONFIG="Primary User for rdiffweb: admin, with password: admin123\nPlease login to rdiffweb at http://$MYIP:8080 and change the password."
else
	if [[ $INSTALLEDVER == "0.6.3" ]]; then
		# for earlier versions of rdiffweb we should overwrite the conf file with newer:
		# old conf contained settings that are now irrelevant and new one is a template anyway
		cp -a rdw.conf /etc/rdiffweb || { echo "An error occurred copying rdw.conf to /etc/rdiffweb, aborting..." >&2; exit 6; }
		chown root:root /etc/rdiffweb/rdw.conf
		chmod 644 /etc/rdiffweb/rdw.conf
	fi
	RDWCONFIG="Pre-existing user configuration was not changed\nRerun with -f option if you need to reset user configuration"
fi
[[ -n $DEBUG ]] && echo "got here 20"

# check we have conf file
[ -f "/etc/rdiffweb/rdw.conf" ] || { echo "An error occurred: rdw.conf could not be found, aborting...">&2; exit 8; }

# start rdiffweb
/etc/init.d/rdiffweb start || { echo "An error occurred starting rdiffweb, aborting...">&2; exit 12; }
[[ -n $DEBUG ]] && echo "got here 30"

# test that rdiffweb homepage can be reached
echo -n "Visiting rdiffweb homepage http://$MYIP:8080 : "
sleep 5s
[ `wget -q -O - "http://$MYIP:8080"|grep -c rdiffweb` -ge 1 ] || { echo -e "FAILED\nAn error occurred accessing rdiffweb homepage, aborting...">&2; exit 13; }
echo "OK"

[[ $INSTALLEDVER == "0.6.3" ]] && echo "Removing startup for rdiff-web v$INSTALLEDVER" && update-rc.d -f rdiff-web remove && rm -f /etc/init.d/rdiff-web
echo "Setting rdiffweb v$RDWVER to run at startup" && update-rc.d rdiffweb defaults

# final message
echo -e "\nrdiffweb was successfully installed!\n$RDWCONFIG"

exit 0
