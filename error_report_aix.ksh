#!/usr/bin/ksh
#
# Written by Shyamkumar Chauhan
#
# Setup variables.
# Note: TZ will need to be set accordingly so date returns yesterdays date!
#
#Exclude below Errors
#1. Error Class "S"
#2. Error Type "T"
#3. Error Code A924A5FC => SYSPROC
#4. Error Code DCB47997 => DISK OPERATION ERROR
#5. Error Code A6F5AE7C => PATH HAS RECOVERED
#6. Error Code 4B436A3D => LINK ERROR
#7. Error Code C62E1EB7 => DISK OPERATION ERROR
#8. Error Code DE3B8540 => PATH HAS FAILED
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
HOSTNAME=$( hostname )
SCRIPT=$( print ${0##*/} )
TIMESTAMP=$(date +%d%m%Y)
ERRPT_TIMESTAMP=$( date +"%m%d....%y" )
TZ_ORIG=$( print ${TZ} )
TZ=CET-1DST
ERRPT_TIMESTAMP_YESTERDAY=$( date +"%m%d....%y" )
TZ=$( print ${TZ_ORIG} )
TYPE=ERROR
RUN_DATE=$( date +"%d-%b-%Y" )
#
# Check the error log.
#
for ERROR in $( errpt | egrep -vw "S|T|A924A5FC|DCB47997|A6F5AE7C|4B436A3D|C62E1EB7|DE3B8540"| egrep -w "P" | grep -e ${ERRPT_TIMESTAMP} -e ${ERRPT_TIMESTAMP_YESTERDAY} | \
        awk ' { arr[$1]=$1 } END { for ( no in arr ) { print arr[no] } }' )
do
        OCCURS=$( errpt | grep -e ${ERRPT_TIMESTAMP} -e ${ERRPT_TIMESTAMP_YESTERDAY} | \
                grep -c ${ERROR} )
        INSTANCE="Error Report"
        TEXT=$( errpt | grep -e ${ERRPT_TIMESTAMP} -e ${ERRPT_TIMESTAMP_YESTERDAY} | \
                grep ${ERROR} | \
                head -1 | awk '{ print $5,$6,$7,$8,$9 }' )
        print  "TYPE=${TYPE}\nServername=${HOSTNAME}\nReport=${INSTANCE}\nERROR_DATE=${RUN_DATE}\nOCCURENCE=${OCCURS}\nERROR_DETAIL=${TEXT}" > /tmp/error_report.log
        mailx -s "Error on $HOSTNAME " unixteam@company.com < /tmp/error_report.log
done
