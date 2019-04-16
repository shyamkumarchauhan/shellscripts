#!/bin/sh
# This is a script which automatically kills frmweb processes if the have used more that 1000 CPU minutes.
# Script has been created by ShyamKumar Chauhan
#
DIR=/usr/local/bin
cd $DIR
LOG=cpu_proc.log

echo "Analysis for CPU consuming processes started at `date` on `hostname`" >> $LOG

for a in `ps aux |egrep "FND|frmweb" |grep -v grep |grep -v defunct| awk '{print $2}'`
do
        CPU=`ps -e |grep $a |grep -v grep |grep -v opmn |grep -v httpd |awk '{print $3}' |cut -d: -f1`
        if [ $CPU -gt 1000 ]
        then
                ps -ef@ |grep $a |grep -v grep >> $LOG
                ps aux |grep $a |grep -v grep >> $LOG
                WPAR=`ps -ef@ |grep $a |grep -v grep |awk '{print $1}'`
                if [ $WPAR = Global ]
                then
                        $WPAR=`hostname`
                fi
                echo "Process with PID = $a on $WPAR has used more than 1000 CPU minutes. Please check if the process is a run-away process." > ud
                echo "" >> ud
                ps -ef@ |head -1 >> ud
                ps -ef@ |grep $a |grep -v grep >> ud
                echo "" >> ud
                ps aux |head -1 >> ud
                ps aux |grep $a |grep -v grep >> ud
                mailx -s "Process WARNING on $WPAR at `date`" unixteam@company.com < ud
        fi
done

echo "Analysis for CPU consuming processes ended at `date` on `hostname`" >> $LOG

# Rotate logfile
SIZE=`/usr/bin/wc -l $LOG |awk '{print $1}'`
if [ $SIZE -gt 1000 ]
then
        mv $LOG $LOG.old
        touch $LOG
fi
