#!/bin/bash
#  zimbashckup.sh
#  
#  Copyright 2013 Cyril Lavier <bainisteoir@davromaniak.eu>
#  
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  

usage() {
	echo "USAGE: $0 [OPTIONS]"
	echo "ZimBashckup : Zimbra Backup Script in Bash"
	echo ""
	echo -e " -v | --verbose\t\t\t\t\tVerbose/debug mode, displays the status of the current task running."
	echo -e " -u | --unite\t\t\t\t\tBackup whole mailbox at the time, default behavior is to backup every folder separately."
	echo -e " -p [cmd] | --postscript=[cmd]\t\t\tScript/command to launch after the backup."
	echo -e " -m [mailboxes] | --mailboxes=[mailboxes]\tBackup only this/these mailboxes (each mailbox separated by a space), default behavior is to backup all mailboxes."
	echo -e " -d [domains] | --domains=[domains]\t\tBackup only mailboxes which belong to this/these domains (each domain separated by a space), default behavior is to backup all mailboxes. Can't be used with option \"-m | --mailbox\"."
	echo -e " -f [tar|tgz|zip] | --format=[tar|tgz|zip]\tFormat used to store backups (this is given to zmmailbox getRestURL command). Default is tar"
	echo -e " -V | --version\t\t\t\t\tDisplay version information."
	echo -e " -c | --changelog\t\t\t\tDisplay changelog information."
	echo -e " -h | --help\t\t\t\t\tDisplay this help."
	echo -e " -l | --locale\t\t\t\t\tChoose the locale used for the backup process (default is \"en_US.UTF-8\")"
	echo -e "    | --dest\t\t\t\t\tChoose the destination folder (defaut is \"/opt/zimbra/backups\"). Needs to be writable by the zimbra user"
}

changelog() {
	echo "V0.1: December 25th 2013 : First release"
	echo "See the CHANGELOG for more information"
}

version() {
	echo "ZimBashckUP V0.1"
	echo "Written by Cyril Lavier <bainisteoir(at)davromaniak(dot)eu>"
}

echoerror() {
	echo "ERROR : "$* >&2
}

echoverbose() {
	if [ ! -z "$VERBOSE" ]; then
		echo "$*"
	fi
}

checkrequirements() {
        ret=0
	for i in gawk date; do
		which $i > /dev/null
		if [ $? -gt 0 ]; then
			echoerror "$i is missing"
			ret=1
		fi
	done
	which zmcontrol > /dev/null
	if [ $? -gt 0 ]; then
		echoerror "zmcontrol is missing, this means you either don't have Zimbra installed on this server or the PATH variable is not correctly set under the zimbra user account"
		ret=1
	fi
	return $ret
}        

main_zimbashckup() {
	ZHOME=/opt/zimbra
	ZCONFD=$ZHOME/conf
	DATE=$(date +%Y/%m/%d)
	ZMBOX=/opt/zimbra/bin/zmmailbox
	if [ -z "$LOCALE" ]; then
		LOCALE="en_US.UTF-8"
	fi
	echo "Locale : $LOCALE"
	export LANG=$LOCALE
	export LC_ALL=$LOCALE
	if [ -z "$FORMAT" ]; then
		FORMAT="tar"
	fi
	if [ -z "$DEST" ]; then
		ZBACKUP=$ZHOME/backup/mailbox
	else
		ZBACKUP=$DEST
	fi
	ZDUMPDIR=$ZBACKUP/$DATE
	if [ -z "$MBOXES" ] && [ -z "$DOMAINS" ]; then
		MBOXES=$(zmprov -l gaa)
	elif [ ! -z "$DOMAINS" ]; then
		MBOXES=$(for d in $DOMAINS; do zmprov -l gaa $d;done)
	fi
	if [ ! -d $ZDUMPDIR ]; then
		mkdir -p $ZDUMPDIR
	fi
	for mbox in $MBOXES; do
		FOLDERS=''
		test -d $ZDUMPDIR/${mbox} || mkdir -p $ZDUMPDIR/${mbox}/
		if [ -z "$UNITE" ]; then
			echoverbose "\_ $mbox"
			FOLDERSRAW=$($ZMBOX -z -m $mbox getAllFolders | tail -n +4 | awk '{ if($4 > 0){$1=""; $3=""; $4=""; print $0 } }' | sed -e "s/  */ /g" | sed -e "s/^ *//")
			if [ $(echo $FOLDERSRAW | wc -c) -gt 1 ]; then
				while read type fname; do
					$ZMBOX -z -m $mbox getFolder "$(echo $fname | sed -e "s/ (.*:.*)//")" | grep -q 'ownerDisplayName'
					ret=$?
					if [ "$ret" -gt "0" ]; then
						FOLDERS=$(echo -ne "${FOLDERS}\n${fname}")
					fi
				done < <(echo "$FOLDERSRAW")
			fi
		else
			FOLDERS="/"
			echoverbose "\_ $mbox => $ZDUMPDIR/${mbox}/full.$FORMAT"
		fi
		test -z "$FOLDERS" && echoverbose '    Nothing to backup here...'
		while read fname; do
			if [ -z "$UNITE" ]; then
				folder=$(echo $fname | sed -e "s/::space::/ /g")
				filefoldername=$(echo $fname | sed -e "s?/?.?g" | sed -e "s/^\.//")
				echoverbose '    \_ '"$folder => $ZDUMPDIR/${mbox}/${filefoldername}.$FORMAT"
			else
				folder="$fname"
				filefoldername="full"
			fi
			$ZMBOX -t 600 -z -m $mbox getRestURL "$folder/?fmt=$FORMAT" > "$ZDUMPDIR/${mbox}/${filefoldername}.$FORMAT"
			ret=$?
			if [ "$ret" -gt "0" ]; then
				echoerror "Unable to backup folder $folder, skipping"
			fi
			sleep 1
		done < <(echo "$FOLDERS"  | grep -v "^$")
		zmprov ga $mbox zimbraMailSieveScript > "$ZDUMPDIR/${mbox}/filters.sieve"
		echoverbose '    \_ Mail filters (in sieve format)'" => $ZDUMPDIR/${mbox}/filters.sieve"
		unset FOLDERS FOLDERSRAW
	done
	if [ ! -z "$POSTSCRIPT" ]; then
		exec $POSTSCRIPT
	fi
}

export -f main_zimbashckup

case "$(id -nu)" in
	root)
		echo $0 |grep -qE "^/" && progname=$0 || progname=$PWD/$0
		set -- `getopt -n$0 -u --longoptions="verbose unite postscript: mailboxes: domains: format: version changelog help locale: dest:" "vup:m:d:f:Vchl: " "$@"`
		args="$@"
		su - zimbra --command="FROMROOT=1 $progname ${args}"
		;;
	zimbra)
		if [ -z "$FROMROOT" ]; then
			set -- `getopt -n$0 -u --longoptions="verbose unite postscript: mailboxes: domains: format: version changelog help locale: dest:" "vup:m:d:f:Vchl: " "$@"`
		fi
		while [ $# -gt 0 ]; do
			case "$1" in
				-h|--help)
					usage
					exit 0
					;;
				-V|--version)
					version
					exit 0
					;;
				-c|--changelog)
					changelog
					exit 0
					;;
				-v|--verbose)
					VERBOSE="yes"
					;;
				-u|--unite)
					UNITE="yes"
					;;
				-p|--postscript)
					POSTSCRIPT="$2"
					shift
					;;
				-l|--locale)
					LOCALE="$2"
					echo $2
					shift
					;;
				--dest)
					test -w $2
					if [ $? -eq "1" ]; then
						echoerror "Directory $2 doesn't exists or is not writable by the zimbra user"
						exit 13
					fi
					DEST="$2"
					shift
					;;
				-m|--mailboxes)
					MBOXES=$2
					shift
					echo $2 | grep -vq "^-"
					v=$?
					while [ $v -eq "0" ]; do
						MBOXES=$MBOXES" "$2
						shift
						if [ "x"$2 == "x" ]; then
							v=1
						else
							echo $2 | grep -vq "^-"
							v=$?
						fi
					done
					;;
				-d|--domains)
					DOMAINS=$2
					shift
					echo $2 | grep -vq "^-"
					v=$?
					while [ $v -eq "0" ]; do
						DOMAINS=$DOMAINS" "$2
						shift
						if [ "x"$2 == "x" ]; then
							v=1
						else
							echo $2 | grep -vq "^-"
							v=$?
						fi
					done
					;;
				-f|--format)
					echo $2 | grep -qE "(tgz|tar|zip)"
					ret=$?
					if [ $ret -gt "0" ]; then
						echoerror "The format must be one on these three values : tar, tgz, zip."
						exit 10
					fi
					#echo $2
					FORMAT="$2"
					shift
					;;
				--)
					shift
					;;
			esac
			shift
		done
		checkrequirements
		if [ $? -gt 0 ]; then
			echoerror "Please install the missing tools and rerun this script"
			exit 11
		fi
		if [ ! -z "$MBOXES" ] && [ ! -z "$DOMAINS" ]; then
			echoerror "You can't use --mailboxes and --domains alltogether"
			exit 12
		fi
		main_zimbashckup
		;;
	*)
		echo "Please run this program using either the root or the zimbra user"
		exit 1
esac
