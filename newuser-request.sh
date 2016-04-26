#!/bin/bash
#
# newuser-request.sh
#
# process files created by TimeDicer webserver to add new users
# this should be run each minute by crontab
#
# changelog:
# 6.0426 - bugfix determining new uid/gid (bug since 6.0422, only affected BASEID>1)
# 6.0423 - use new script (kudos: Grant Emsley) to create rdiffweb user
# 6.0422 - fix uid and gid to be the same and to be the lowest number not in use within the 'range';
#          but allow range to be defined (in thousands) by the last digit of either the hostname
#          (if it is a digit) or of the value in /opt/baseid - this makes it possible to have
#          unique uids/gids for say 'timedicer1' and 'timedicer2' machines so that they can
#          perform mutual backup with timedicer-mirror using -b.
# 5.1224 - tidy up, make message compatible with rdiffweb 0.8.2.dev1 but depends
#          on /usr/local/bin/rdiff-web-config from rdiffweb 0.6.3
# 4.0909 - set ~/.ssh to 700 permission (not 755)
# 2.0616 - don't fail if .ssh subdir already exists (e.g. recreating user after deletion)
# 1.1009 - fix bug which rejected a new username if it was part of an existing username
# 1.0915 - use ip on 1st network device of any type (not just eth)
# 1.0830 - create rdiffWeb user
VERSION="6.0426"
failed_cleanup() {
	rm -f $1.failed
	mv $1.txt $1.failed
	mv $1.rsp $1.php
}

FOLDER=/var/www/.adduser

for i in `ls $FOLDER/*.txt 2>/dev/null`; do
	[[ -z $START ]] && START=`date +"%c"`
	[[ -z $MYIP ]] && MYIP="$(hostname -I|cut -d" " -f1)"; [ -z "$MYIP" ] && MYIP=127.0.0.1

	USERNAME=`basename $i .txt`
	echo "<ul><li>Started processing $USERNAME $START</li>" >>$FOLDER/$USERNAME.rsp
#	count current users with same name (must be 0)
	if [ 0 != `cat /etc/passwd|mawk -F : '{print $1}'|grep -cx $USERNAME` ]; then
		echo "<li>$USERNAME: there is already a user with this name. Aborting...</li></ul>" >>$FOLDER/$USERNAME.rsp
		failed_cleanup $FOLDER/$USERNAME
		continue
	fi
	echo "<li><pre>" >>$FOLDER/$USERNAME.rsp
	# establish the BASEID from which we come up with a new uid and gid, normally 1 (i.e. use 1001+)
	#   it can be defined as the last digit in /opt/baseid, or if hostname ends in a digit it uses that digit
	[[ -s /opt/baseid ]] && BASEID=$(cat /opt/baseid) || BASEID=$(hostname)
	BASEID=$(echo $BASEID|tail -n1|awk '{BASEID=substr($1,length($1)); if (BASEID+0>=1) {print BASEID} else {print 1}}')
	# check against existing uids and gids and choose the next lowest number that is available within the range
	NEWID=$(awk -v BASEID=$BASEID -F: 'BEGIN {MAXID=BASEID*1000} ($3>BASEID*1000) && ($3<(BASEID+1)*1000) && ($3!=65534) {ID=$3; if ($4>ID) ID=$4; if (MAXID<ID) MAXID=ID} END {print MAXID+1}' /etc/passwd)
	# it should be impossible to get non-numeric NEWID or NEWID<1001 but just in case...
	[[ $NEWID -ge 1001 ]] || { echo "</pre></li><li>Unable to add user '$USERNAME', invalid UID/GID '$NEWID' was generated" >>$FOLDER/$USERNAME.rsp; failed_cleanup; continue; }
	# create the group
	addgroup --gid $NEWID $USERNAME || { echo "</pre></li><li>Unable to add group '$USERNAME' gid $NEWID, the command: <pre>addgroup --gid $NEWID $USERNAME</pre> produced error $?</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }
	# create the user
	adduser --disabled-password --uid $NEWID --gid $NEWID --gecos $USERNAME $USERNAME>>$FOLDER/$USERNAME.rsp 2>&1 || { echo "</pre></li><li>Unable to add user '$USERNAME', the command: <pre>adduser --disabled-password --gecos $USERNAME $USERNAME</pre> produced error $?</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }
	echo "</pre></li>" >>$FOLDER/$USERNAME.rsp

	mkdir -p /home/$USERNAME/.ssh || { echo "<li>Unable to create directory /home/$USERNAME/.ssh, the command: <pre>mkdir /home/$USERNAME/.ssh</pre> produced error $?</li>" >>$folder/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }
	echo "<li>/home/$USERNAME/.ssh directory created</li>" >>$FOLDER/$USERNAME.rsp

	head -n 1 $i>/home/$USERNAME/.ssh/authorized_keys || { echo "<li>Unable to move public key to .ssh directory</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }
	echo "<li>/home/$USERNAME/.ssh/authorized_keys file created</li>" >>$FOLDER/$USERNAME.rsp

	chown -R $USERNAME: /home/$USERNAME/.ssh || { echo "<li>Unable to change ownership of .ssh directory</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }

	chmod 700 /home/$USERNAME/.ssh || { echo "<li>Unable to change permissions for .ssh directory</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }

	chmod 600 /home/$USERNAME/.ssh/authorized_keys || { echo "<li>Unable to change permissions for authorized_keys file</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }

	PASSWORD=`tail -n 1 $i`
	# use Grant Emsley <grant@emsley.ca> script [23 Apr 2016]
	# Usage: ./rdiffweb-adduser.py username -p password -d /home/username -e user@example.com
	/opt/rdiffweb-adduser.py "$USERNAME" -p "$PASSWORD" -d "/home/$USERNAME" || { echo "<li>Unable to setup rdiff-web user</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }
	# old script (from rdiffweb v0.6.3) no longer works:
	#rdiff-web-config adduser "$USERNAME" "$PASSWORD" /home/"$USERNAME" || { echo "<li>Unable to setup rdiff-web user</li></ul>" >>$FOLDER/$USERNAME.rsp; failed_cleanup $FOLDER/$USERNAME; continue; }

	##	add primary user ssh key(s) into file $sshkey - this is you!
	#	PRIMARYUSER=$(awk -F: '{if ($3==1000) printf $1}' /etc/passwd)
	#	[[ -s /home/$PRIMARYUSER/.ssh/id_rsa.pub ]] && cat /home/$PRIMARYUSER/.ssh/id_rsa.pub >>$sshkey

	DONE=`date +"%c %H:%M:%S"`
	echo -e "<p>Your subscription request for a backup facility on TimeDicer Server $MYIP has now been granted as user '$USERNAME'.</p><p>You can now use TimeDicer (or rdiff-backup) to create backups of your data, and earlier versions will be retained, so that you can later recover the latest or an earlier version of a file, or even a deleted file.</p>\
<p>To recover files, log into the rdiffWeb interface of this TimeDicer Server at http://$MYIP:8080, with username '$USERNAME' and the password'$PASSWORD'. If you don&rsquo;t see any Backup Locations when you log into rdiffWeb, click on 'User settings' and then 'Refresh repositories'.</p>
<p>For authentication when connecting to this TimeDicer Server with TimeDicer Client or rdiff-backup you must use the private key that matches the public key submitted in your subscription request. For more information, consult your administrator.</p>\
<p>The actions and output of this page were generated by /opt/newuser-request.sh v$VERSION.</p>
<p>Thank you for using TimeDicer.</p>" >$FOLDER/$USERNAME.rsp
	rm $i
	#mv $i $FOLDER/$USERNAME.don
	# make the text responses available to webserver
	mv $FOLDER/$USERNAME.rsp $FOLDER/$USERNAME.php
done
