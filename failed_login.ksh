#!/bin/ksh
#---------------------------------------------------------------------------
#
#         Filename:  failed_login.ksh
#
#      Description:  Monitor program to monitor all the oratab 'Y' marked
#                    database's ALERT LOG file for exceptions.
#
#           Author:  ShyamKumar Chauhan
#
#
#       Example root's crontab entry:
#       15,45 * * * * /mnt/nim/scripts/failed_login.ksh mail" > /dev/null 2>&1
#
#       Tip: To avoid a lot of email from the first run, you should run it by hand without
#               the mail option.
#
#---------------------------------------------------------------------------
#
# Initialize the variables that are to be used in this script.
#
OSA='unixteam@company.com'
mailme=$1
HOST=`hostname`
FAI_HOME=/var/adm
TEMP=/tmp/temp$$
if [ ! -f $FAI_HOME/.lccount ]
then
        echo 1 > $FAI_HOME/.lccount
fi
lcfrom=`cat $FAI_HOME/.lccount`
lcto=`cat $FAI_HOME/messages |wc -l`
if [ "$lcfrom" -gt "$lcto" ]
then
echo 1 > $FAI_HOME/.lccount
fi
if [ "$lcto" -gt "$lcfrom" ]
then
        cat $FAI_HOME/messages |tail -`expr ${lcto} - ${lcfrom} + 1` |grep -i "failed" |grep -v "gethostbyaddr" > $TEMP
        echo $lcto > $FAI_HOME/.lccount
        LN_CNT=`wc -l < $TEMP`
        if [[ $LN_CNT -ge 1 ]]
        then
                if [ "$mailme" = 'mail' ]
                then
                        mailx -s "Please check the system log on $HOST for failed logins" $OSA < $TEMP
                fi
        fi
        rm -f $TEMP
fi
