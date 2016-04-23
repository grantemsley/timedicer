#!/bin/bash
# add/update options in crontab
# 17Oct2015: added anacron installation so that cron.daily/weekly/monthly actions are triggered in /etc/crontab
function EditOrAdd() {
# param 1: text to check for, param 2: full line to replace/add
if [ `egrep -c "$1" /etc/crontab` -gt 0 ]; then
	sed -i "/$1/sZ.*Z$2Z" /etc/crontab
else
	echo $2|sed 'sZ\\ZZg'>>/etc/crontab
fi
}
[ -z "$1" ] && echo -e "$0\n\nAdd/Update root crontab [/etc/crontab]\n\nRequired parameter missing: email address\nNo action taken" && exit 1
apt-get install -qqy anacron
EditOrAdd "MAILTO=" "MAILTO=$1"
EditOrAdd "lvm{0,1}-usage" "24 14 \* \* \* root /opt/lvm-usage.sh -fq 70"
EditOrAdd "newuser-request" "\*  \*  \* \* \* root /opt/newuser-request.sh"
#EditOrAdd "timedicer-verify" "3 10 \* \* \* root /opt/timedicer-verify /opt/rdiff-backup-fv"
#"echo -e MAILTO=$1\\n24 14 \* \* \* root /opt/lv-usage.sh -q 70\\n\*  \*  \* \* \* root /opt/newuser-request.sh\n3 3 \* \* \* root /opt/fix-restore-log.sh" "/etc/crontab"
