#!/bin/bash
#
# create-user.sh
#
# Creates a new TimeDicer user, instead of using it's web interface
#
VERSION="5.1224"

START=`date +"%c"`
MYIP="$(hostname -I|cut -d" " -f1)"; [ -z "$MYIP" ] && MYIP=127.0.0.1

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
exit 1;

#	count current users with same name (must be 0)
if [ 0 != `cat /etc/passwd|mawk -F : '{print $1}'|grep -cx $USERNAME` ]; then
	echo "$USERNAME: there is already a user with this name. Aborting..."
fi

adduser --disabled-password --gecos $USERNAME $USERNAME || { echo "Unable to add user '$USERNAME', the command: <pre>adduser --disabled-password --gecos $USERNAME $USERNAME produced error $?"; exit; }
echo " --- System user created ---"

mkdir -p /home/$USERNAME/.ssh || { echo "Unable to create directory /home/$USERNAME/.ssh, the command: mkdir /home/$USERNAME/.ssh produced error $?"; exit; }
touch /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME: /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
echo " --- .ssh folder created ---"

rdiff-web-config adduser "$USERNAME" "$PASSWORD" /home/"$USERNAME" || { echo "Unable to setup rdiff-web user"; exit; }
