#!/bin/bash
#
# create-user.sh
# Written by Grant Emsley <grant@emsley.ca>
#
# Creates a new TimeDicer user from the command line, instead of using it's web interface
# Does not add an SSH key, but does set up the appropriate folders so SSH keys can be managed from rdiff-web.


START=`date +"%c"`

USERNAME=$(echo $1 | sed -e 's/[^A-Za-z0-9]//g')
if [ "$USERNAME" = "" ]
then
	echo "INVALID USERNAME SUPPLIED"
	echo "Usage: /opt/create-user.sh username password"
	exit
fi

PASSWORD=$2
if [ "$PASSWORD" = "" ]
then
	echo "INVALID PASSWORD SUPPLIED"
	echo "Usage: /opt/create-user.sh username password"
	exit
fi

echo "Creating new backup user $USERNAME"

#	count current users with same name (must be 0)
if [ 0 != `cat /etc/passwd|mawk -F : '{print $1}'|grep -cx $USERNAME` ]; then
	echo "$USERNAME: there is already a user with this name. Aborting..."
fi

# establish the BASEID from which we come up with a new uid and gid, normally 1 (i.e. use 1001+)
#   it can be defined as the last digit in /opt/baseid, or if hostname ends in a digit it uses that digit
[[ -s /opt/baseid ]] && BASEID=$(cat /opt/baseid) || BASEID=$(hostname)
BASEID=$(echo $BASEID|tail -n1|awk '{BASEID=substr($1,length($1)); if (BASEID+0>=1) {print BASEID} else {print 1}}')
# check against existing uids and gids and choose the next lowest number that is available
NEWID=$(awk -v BASEID=$BASEID -F: 'BEGIN {MAXID=BASEID*1000} ($3>BASEID*1000) && ($3<(BASEID+1)*1000) && ($3!=65534) {ID=$3; if ($4>ID) ID=$4; if (MAXID<ID) MAXID=ID} END {print MAXID+1}' /etc/passwd)
# it should be impossible to get non-numeric NEWID or NEWID<1001 but just in case...
[[ $NEWID -ge 1001 ]] || { echo "Unable to add user '$USERNAME', invalid UID/GID '$NEWID' was generated"; exit; }

echo " --- Creating system user with UID/GID $NEWID --- "
adduser --disabled-password --uid $NEWID --gecos $USERNAME $USERNAME || { echo "Unable to add user '$USERNAME', the command: <pre>adduser --disabled-password --gecos $USERNAME $USERNAME produced error $?"; exit; }
echo " --- System user created ---"

mkdir -p /home/$USERNAME/.ssh || { echo "Unable to create directory /home/$USERNAME/.ssh, the command: mkdir /home/$USERNAME/.ssh produced error $?"; exit; }
touch /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME: /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
echo " --- .ssh folder created ---"

/opt/rdiffweb-adduser.py "$USERNAME" -p "$PASSWORD" -d "/home/$USERNAME" || { echo "Unable to setup rdiff-web user"; exit; }
echo " --- rdiff-web user account created ---"
