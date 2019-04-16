#!/usr/bin/ksh93
#---------------------------------------------------------------------------
#
#         Filename:  mksysdoc-aix.ksh
#
#      Description:  Collect the SyetmDocumentation for ALL VIOS and AIX Servers
#
#           Author:  ShyamKumar Chauhan
#
#
#       Example root's crontab entry:
#      0 6 * * 6 /usr/local/bin/mksysdoc-aix.ksh > /dev/null 2>&1
#
#
#---------------------------------------------------------------------------
#
# Initialize the variables that are to be used in this script.
#
#
##############################################################################
##                             Global declerations                          ##
##############################################################################
#
OIFS=$IFS
set -A Month "" Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
[ -d /usr/ios ] && ISVIOserver=true
[ -x /opt/VRTSvcs/bin/haclus ] && ISVCSserver=true
OUTROOT=/var/Systemdocumentation
TODAY=$(date +'%Y%m%d')
HOST=$(hostname)
if [ ! -d $OUTROOT ]
then
mkdir -p $OUTROOT
fi
find $OUTROOT/$HOST/* -type d -ctime +8 -exec rm -rf {} \;
#############################################################################
#  goto MAIN                                                                #
#############################################################################
##############################################################################
##                               Utility functions                          ##
##############################################################################
#
function chardate
{
   timeinsecs=${1}
   s=${1:-0}
   n=$(((4*${l:=$(($s/86400+68569+2440588))})/146097))
   i=$(((4000*(${p:=$(($l-(146097*$n+3)/4))}+1))/1461001))
   j=$(((80*${r:=$(($p-(1461*$i)/4+31))})/2447))
   year=$((100*($n-49)+$i+($j/11)))
   month=$(($j+2-(12*($j/11))))
   day=$(($r-(2447*$j)/80))
   hour=${H:=$((${t:=$(($s-86400*($s/86400)))}/3600))}
   minute=${M:=$((($t-$H*3600)/60))}
   second=$(($t-$H*3600-$M*60))
   now=$(date +%s)
   (( halfyearold=$now-15552000 ))
   if [[ $timeinsecs -lt $halfyearold ]] ;then # m d y
      printf "%s %2.2d %4.4d\n" "${Month[$month]}" ${day} ${year}
   else
      printf "%s %2.2d %2.2d:%2.2d\n" "${Month[$month]}" ${day} ${hour} ${minute}
   fi
}

function error
{
   echo "$*" >&2
   exit
}
#
##############################################################################
##                            VIO related functions                         ##
##############################################################################
#
function VIO_System
{
   mkdir ${0}
   cd ${0}

   /usr/ios/cli/ioscli ioslevel > IOSlevel 2> /dev/null
   rm -f ioscli.log

   cd ..
}

function VIO_Disks
{
# en hdisk kan være:
# -intern disk brugt lokalt eg. rootvg
# -intern disk delt op i virtuelle diske = lv => lokal VG = OS_VG1-5
# -intern disk videregivet som virtuelle diske
# -intern disk free
# -lokal fil - ikke brugt her
# -SAN subdisk
# -SAN disk brugt lokalt =>  VG, ikke behov for - ikke brugt her
# -SAN disk delt op i virtuelle = lv => VG - ikke brugt her
# -SAN disk videregivet som virtuel disk
# -SAN disk free
   mkdir ${0}
   cd ${0}
   # Start to collect all the pices of information we need
   typeset -A subdisks
   typeset -A backingdevices
   # find subdiske:
   /usr/ios/cli/ioscli lspv|grep power|while read pd r
   do
      powermt display dev=$pd|grep hdisk|while read n hba hdisk rest
      do
         subdisks[$hdisk]=$pd
      done
   done
   # find backing devices:
   /usr/ios/cli/ioscli lsmap -all|egrep -v '^--|^$|^SVSA|0x00000000|NO VIRTUAL'| while read v1 v2 v3
   do
      if [ -z $v3 ] ;then
         eval "$v1=$v2"
         if [ "$v1" = "Physloc" ] ;then
            backingdevices[$Backing]=$VTD
         fi
      elif [ "$v1" = "Backing" ] ;then
         eval "$v1=$v3"
      else
         vhost=$v1
         slot=$v2
         lpar=$v3
      fi
   done

   { # Disklist
      printf "%s\t%s\t%s\t%s\t%s\n" "hdisk" "PVID" "Parent-Disk / Virtual-Disk / Volumegroup"  "Size (GB)" "description"
      /usr/ios/cli/ioscli lspv|tail +2|while read disk pvid vg status
      do
         /usr/ios/cli/ioscli lsdev -dev $disk|tail +2|read hdisk avail description
         Size=$(($(bootinfo -s $disk)/1024))
         [ $Size -eq 0 ] && Size=''
         if [ ! -z ${backingdevices[$disk]} ] ;then
            parentdisk=${backingdevices[$disk]}
         elif [ $vg != None ] ;then
            parentdisk="$vg"
         else
            parentdisk=${subdisks[$hdisk]}
            if [ -z $Size ] ;then
               Size=$(($(bootinfo -s $parentdisk)/1024))
            fi
         fi
         printf  "%s\t%s\t%s\t%s\t%s\n" "$disk" "$pvid" "$parentdisk" "$Size" "$description"
         VIO_disk $disk
      done
   } > Disklist
   rm -f ioscli.log

   cd ..
}

function VIO_disk
{
   mkdir ${1}
   cd ${1}

   if [ ${1%%[0-9]*} = hdiskpower ] ;then
       powermt display dev=$1 > "CLARiiON Info"
   fi

   /usr/ios/cli/ioscli lsdev -dev ${1} -attr > "VIO Disk Attributes"
   rm -f ioscli.log

   cd ..
}

function VIO_Network
{
   mkdir ${0}
   cd ${0}

   for seadev in $(/usr/ios/cli/ioscli lsmap -all -net|grep SEA|grep -v "NO SHARED"|awk '{ print $2 }')
   do
      { # Shared Ethernet adapter $seadev
         printf  "%s\t%s\t%s\n" "Attribute" "Value" "Description"
         /usr/ios/cli/ioscli lsdev -dev $seadev -attr|tail +3|while read Attribute Value Description
          do
             Description=${Description%True}
             printf  "%s\t%s\t%s\n" "$Attribute" "$Value" "$Description"
          done
      } > "Shared Ethernet adapter $seadev"
   done
   rm -f ioscli.log

   cd ..
}

function VIO_Devices
{
   mkdir ${0}
   cd ${0}

   { # Virtual Device Information
      printf  "%s\t%s\t%s\n" "Name" "Status" "Description"
      /usr/ios/cli/ioscli lsdev -virtual|tail +2| while read Name Status Description
      do
         printf  "%s\t%s\t%s\n" "$Name" "$Status" "$Description"
      done
   } > "Virtual Device Information"

   { # Adapter Information
      printf  "%s\t%s\t%s\n" "Name" "Status" "Description"
      /usr/ios/cli/ioscli lsdev  -type adapter|tail +2| while read Name Status Description
      do
         printf  "%s\t%s\t%s\n" "$Name" "$Status" "$Description"
      done
   } > "Adapter Information"

   { # Slot Information
      printf  "%s\t%s\t%s\n" "Slot" "Description" "Device"
      /usr/ios/cli/ioscli lsdev -slots|tail +2| while read Slot Description Device
      do
         printf  "%s\t%s\t%s\n" "$Slot" "$Description" "$Device"
      done
   } > "Slot Information"
   rm -f ioscli.log

   cd ..
}

function VIO_Mapping
{
   mkdir ${0}
   cd ${0}

   { # VIO Mapping by NPIV
     printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Client ID" "Client Name" "Physical Location" "FC Name" "Status" "VFC Client"
     /usr/ios/cli/ioscli lsmap -all -npiv -field  "FC name" Status Name clntid ClntName physloc vfcclient -fmt :|while read line
     do
        col1=$(echo ${line}|awk -F: '{print $1}')
        col2=$(echo ${line}|awk -F: '{print $2}')
        col3=$(echo ${line}|awk -F: '{print $3}')
        col4=$(echo ${line}|awk -F: '{print $4}')
        col5=$(echo ${line}|awk -F: '{print $5}')
        col6=$(echo ${line}|awk -F: '{print $6}')
        col7=$(echo ${line}|awk -F: '{print $7}')
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}" "${col5}" "${col6}" "${col7}"
     done
   } > "VIO Mapping by NPIV"

   rm -f ioscli.log
   cd ..
}

#
##############################################################################
##                           VCS related functions                          ##
##############################################################################
#
function VCS_information
{
   mkdir ${0}
   cd ${0}

   if [ -x /opt/VRTSvcs/bin/haclus ]; then
   {  # VCS Status
        echo "Status: `hastatus -summary`"
   } > "VCS Status"

   {  # Cluster Attributes
        printf "%s\t%s\n" "Attribute" "Value"
        haclus -display|grep -v "#"|awk '{print $1}'|while read attr
        do
        attr_val=$(haclus -display|grep -v "#"|grep -w "$attr"|awk '{$1=""; print $0}')
        printf "%s\t%s\n" "$attr" "$attr_val"
        done
   } > "Cluster Attributes"

   {  # LLT configuration
        printf "%s\t\t%s%s\n" "Attribute" "Value"
        lltstat -c|sed 's/[        ][   ]*//g'|grep -v LLTconfigurationinformation|cut -d: -f1|while read attr
        do
        attr_val=$(lltstat -c|sed 's/[        ][   ]*//g'|grep -v LLTconfigurationinformation|grep -w "$attr"|cut -d: -f2)
         printf "%s\t\t%s%s\n" "$attr" "$attr_val"
         done
   } > "LLT configuration"

   {  # VCS Systems Information
        printf "%s\t%s\t\t\t%s\t%s\n" "System" "Attribute" "Value"
        hasys -display|grep -v "#"|while read sys attr attr_v
        do
        attr_value=$(hasys -display|grep -w $sys|grep -w $attr|awk '{$1="";$2=""; print $0}')
        printf "%s\t%s\t\t\t%s\t%s\n" "$sys" "$attr" "$attr_value"
        done
   } > "VCS Systems Information"

   {  # Cluster Users
        printf "%s\t%s\n" "UserName" "Privilege"
        hauser -display|tail -n +3|grep -v "^$"|awk '{print $1}'|while read user
        do
        priv=$(hauser -display|tail -n +3|grep -v "^$"|grep -w "$user"|awk '{print $3}')
        printf "%s\t%s\n" "$user" "$priv"
        done
   } > "Cluster Users"

   {  # LLT Node Information
        echo "`lltstat -nvv|tail +2|head -9`"
   } > "LLT Node Information"

   {  # Resource Groups
        printf "%s\t%s\n" "Resource Group"
        hagrp -list|while read col1 col2
        do
        printf "%s\t%s\n" "$col1" "$col2"
        done
   } > "Resource Groups"

   { # Resource Group Parameters
         printf "%s\t%s\t\t%s\t%s\n" "Group" "Attribute" "System" "Value"
         for rg in $(hagrp -list|awk '{print $1}'|uniq)
         do
         hagrp -display $rg|grep -v "#"|while read col1 col2 col3 colo4
         do
         col4=$(hagrp -display $rg|grep -v "#"|grep -w $col1|grep -w $col2|grep -w $col3|tail -1|awk '{$1="";$2="";$3="";print $0}')
         printf "%s\t%s\t\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
         done
         done
    } > "Resource Group Parameters"

   { # Resource State
         printf "%s\t%s\t%s\t%s\n" "Resource" "Attribute" "System" "Value"
         hares -state|grep -v "#"|while read col1 col2 col3 col4
         do
         printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
         done
    } > "Resource State"

   { # Resource Dependency
         printf "%s\t%s\t%s\n" "Group" "Parent" "Child"
         hares -dep|grep -v "#"|while read col1 col2 col3
         do
         printf "%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}"
         done
    } > "Resource Dependency"

   fi
   cd ..
}

#
##############################################################################
##                           System related functions                       ##
##############################################################################
#
function General_Information
{
   mkdir ${0}
   cd ${0}

   {  # System Characteristics
      IFS=:
      printf "%s\t%s\n" "Attribute" "Value"
      case $(oslevel) in
         6*) lines=17;;
         *)  lines=15;;
      esac
      prtconf 2>/dev/null|head -$lines|while read Attribute Value
      do
         printf "%s\t%s\n" "$Attribute" "$Value"
      done
      IFS=$OIFS
   } > "System Characteristics"

   { # System wide settings
      printf "%s\t%s\t%s\n" "Attribute" "Value"  "Description"
      lsattr -El sys0 | while read Attribute Value rest
      do
         rest=${rest%False}
         rest=${rest%True}
         printf "%s\t%s\t%s\n" "$Attribute" "$Value"  "$rest"
      done
      IFS=$OIFS
   } > "System wide settings"

   { # SRC controlled daemons
       printf "%s\t%s\t%s\t%s\n" "Daemon" "Group" "PID" "Status"
       lssrc -a | while read col1 col2 col3 col4
       do
          if [ "$col3" = inoperative ] ;then
             col4=$col3 col3='-'
          elif [ "$col2" = inoperative ] ;then
             col4=$col2 col3='-' col2="N/A"
          fi
          printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
       done
   } > "SRC controlled daemons"

   { # syncd daemon
      printf "%s\t%s\n" "Daemon" "Seconds"
      prog=$(ps -ef -o %a|grep syncd|grep -v grep|cut -f1 -d' ')
      secs=$(ps -ef -o %a|grep syncd|grep -v grep|cut -f2 -d' ')
      printf "%s\t%s\n" "${prog}" "${secs}"
   } > "syncd daemon"

   { # bootlist
      printf "%s\t%s\t%s\n" "Bootdisk" "Bootlv" "Actual boot disk"
      bootlist -m normal -o | while read Bootdisk Bootlv
      do
         if [ "$Bootdisk" = "$(bootinfo -b)" ] ;then
            Actual=yes
         else
            Actual=''
         fi
         printf "%s\t%s\t%s\n" "$Bootdisk" "${Bootlv#blv=}" "$Actual"
      done
   } > "bootlist"

   cd ..
}

function LPAR_information
{
   mkdir ${0}
   cd ${0}

   {  # LPAR Attributes
      IFS=:
      printf "%s\t%s\n" "LPAR Attribute" "Value"
      case $(oslevel) in
         6*) lines=17;;
         *)  lines=15;;
      esac
      lparstat -i|while read Attribute Value
      do
         printf "%s\t%s\n" "$Attribute" "$Value"
      done
      IFS=$OIFS
   } > "LPAR Attributes"

   smtctl > "SMT configuration"
   cd ..
}

function System_Configuration
{
   mkdir ${0}
   cd ${0}

   EtcFiles="aliases environment group inittab passwd profile qconfig rc.shutdown syslog.conf"
   EtcSecurityFiles="group limits login.cfg passwd user roles user.roles"

   { # etc configuration files
   printf "%s\t%s\n" "File" "Description"
   printf "%s\t%s\n" "aliases" "Contains alias definitions for the sendmail command."
   printf "%s\t%s\n" "environment" "The /etc/environment file contains variables specifying the basic environment for all processes."
   printf "%s\t%s\n" "group" "The /etc/passwd file contains basic user attributes."
   printf "%s\t%s\n" "inittab" "Controls the initialization process."
   printf "%s\t%s\n" "passwd" "The /etc/passwd file contains basic user attributes."
   printf "%s\t%s\n" "profile" "Sets the user environment at login time."
   printf "%s\t%s\n" "qconfig" "Configures a printer queuing system."
   printf "%s\t%s\n" "rc.shutdown" "Customized shutdown script."
   printf "%s\t%s\n" "syslog.conf" "Controls output of the syslogd daemon."
   } > "etc configuration files"

   { # security configuration files
   printf "%s\t%s\n" "File" "Description"
   printf "%s\t%s\n" "group" "Contains extended group attributes."
   printf "%s\t%s\n" "limits" "Defines process resource limits for users."
   printf "%s\t%s\n" "login.cfg" "Contains configuration information for login and user authentication."
   printf "%s\t%s\n" "passwd" "Contains extended password attributes."
   printf "%s\t%s\n" "user" "Contains extended user attributes."
   printf "%s\t%s\n" "roles" "The /etc/security/roles file contains the list of valid roles."
   printf "%s\t%s\n" "user.roles" "Contains the list of roles for each user."
   } > "security configuration files"

   { #crontab
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Minute" "Hour" "DayOfMonth" "Month" "Weekday" "Command"
      for user in `ls -l /var/spool/cron/crontabs|awk '{print $9}'|tail -n +2`
      do
      printf "%s\n" "$user"
      crontab -l $user|egrep -v '^;|^#|^$'|while read Minute Hour DayOfMonth Month Weekday Command
      do
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Minute" "$Hour" "$DayOfMonth" "$Month" "$Weekday" "$Command"
      done
      done
   } > "crontab"

   for file in $EtcFiles
   do
      if [ -f "/etc/${file}" ] ;then
         egrep -v '^;|^#|^$'  "/etc/${file}" > ${file}
      else
         echo "File not found" > ${file}
      fi
   done

   for file in $EtcSecurityFiles
   do
      if [ "${file}" = "passwd" ] ;then
         # No encrypted password to be shown !!!!
   egrep -v '^\*|^$'  "/etc/security/${file}" |sed 's/password = .*$/password = ********/' > etc-security-${file}
      elif [ "${file}" = "group" ] ;then
         egrep -v '^\*|^$'  "/etc/security/${file}" > etc-security-${file}
      else
         egrep -v '^\*|^$'  "/etc/security/${file}" > ${file}
      fi
   done

   cd ..
}

function System_Tuning
{
   mkdir ${0}
   cd ${0}

   { # Virtual Memory Manager Tuning
      printf "%s\t%s\n" "VMO Tuning parameter" "Value"
      if [ -x /usr/sbin/vmo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            vmo -a|sed 's/[        ][   ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read vmo
            do
             vmo_tp=$vmo" ="
             vmo_value=$(vmo -a|grep -w "$vmo_tp"|awk '{print $3}')
            printf "%s\t%s\n" "$vmo" "$vmo_value"
         done
         fi
      fi
   } > "Virtual Memory Manager Tuning"

   { # VMO Tuning - next boot
      printf "%s\t%s\n" "Tuning parameter" "Value"
      if [ -x /usr/sbin/vmo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            grep -p vmo /etc/tunables/nextboot|egrep -v : |sed 's/[        ][   ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read vmo
       do
       vmo_tp=$vmo" ="
       vmo_value=$(grep -p vmo /etc/tunables/nextboot|egrep -v : |grep -w "$vmo_tp"|awk '{print $3}')
         printf "%s\t%s\n" "$vmo" "$vmo_value"
        done
         fi
      fi
   } > "VMO Tuning - next boot"

   { # IO Tuning
      printf "%s\t%s\n" "IOO Tuning parameter" "Value"
      if [ -x /usr/sbin/ioo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            ioo -a|sed 's/[        ][   ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read ioo
            do
            ioo_tp=$ioo" ="
            ioo_value=$(ioo -a|grep -w "$ioo_tp"|awk '{print $3}')
          printf "%s\t%s\n" "$ioo" "$ioo_value"
         done
         fi
      fi
   } > "IO Tuning"

   { # IOO Tuning - next boot
      printf "%s\t%s\n" "Tuning parameter" "Value"
      if [ -x /usr/sbin/ioo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            grep -p ioo /etc/tunables/nextboot|egrep -v : |sed 's/[        ][   ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read ioo
         do
          ioo_tp=$ioo" ="
          ioo_value=$(grep -p ioo /etc/tunables/nextboot|egrep -v : |grep -w "$ioo_tp"|awk '{print $3}')
         printf "%s\t%s\n" "$ioo" "$ioo_value"
        done
         fi
      fi
   } > "IOO Tuning - next boot"

   { # Network Tuning
      printf "%s\t%s\n" "NO Tuning parameter" "Value"
      if [ -x /usr/sbin/no ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            no -a|sed 's/[        ][    ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read no
            do
            no_tp=$no" ="
            no_value=$(no -a|grep -w "$no_tp"|awk '{print $3}')
          printf "%s\t%s\n" "$no" "$no_value"
        done
         fi
      fi
   } > "Network Tuning"

   { # Network Tuning - next boot
      printf "%s\t%s\n" "NO Tuning parameter" "Value"
      if [ -x /usr/sbin/no ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            grep -p no /etc/tunables/nextboot|egrep -v : |sed 's/[        ][    ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read no
        do
         no_tp=$no" ="
         no_value=$(grep -p no /etc/tunables/nextboot|egrep -v :|grep -w "$no_tp"|awk '{print $3}')
         printf "%s\t%s\n" "$no" "$no_value"
        done
         fi
      fi
   } > "Network Tuning - next boot"

   { # Scheduler Tuning
      printf "%s\t%s\n" "Scheduler Tuning parameter" "Value"
      if [ -x /usr/sbin/schedo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            schedo -a|sed 's/[        ][        ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read schedo
           do
             schedo_tp=$schedo" ="
             schedo_value=$(schedo -a|grep -w "$schedo_tp"|awk '{print $3}')
             printf "%s\t%s\n" "$schedo" "$schedo_value"
         done
         fi
      fi
   } > "Scheduler Tuning"

   { # Scheduler Tuning - next boot
      printf "%s\t%s\n" "schedo Tuning parameter" "Value"
      if [ -x /usr/sbin/schedo ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            grep -p schedo /etc/tunables/nextboot|egrep -v : |sed 's/[        ][        ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read schedo
          do
           schedo_tp=$schedo" ="
           schedo_value=$(grep -p schedo /etc/tunables/nextboot|egrep -v : |grep -w "$schedo_tp"|awk '{print $3}')
           printf "%s\t%s\n" "$schedo" "$schedo_value"
          done
         fi
      fi
   } > "Scheduler Tuning - next boot"

   cd ..
}
#
##############################################################################
##                         Storage related functions                        ##
##############################################################################
#
#######################    Disk related    ##################################
function Disks
{
   mkdir ${0}
   cd ${0}

   mkdisklist
   emc_inq

   cd ..
}

function mkdisklist
{
   { # Disklist
   printf "%s\t%s\t%s\t%s\t%s\n" "Disk" "PVID/powerdisk" "Volume Group" "Size (GB)" "Description"
   lspv| while read hdisk PVID VG status
   do
      [ ! -z $ISVIOserver ] && [ "x$status" != "xactive" ] && continue
      if [[ "${PVID}" = "none" ]] ;then # Sub disk
         PVID=$(odmget -qvalue=${hdisk} CuAt|grep name|cut -f2 -d\")
         VG=" - "
         Size=" - "
      elif [[ "${VG}" = "None" ]] ;then # Disk not in volumegroup
           Size=$(($(bootinfo -s $hdisk)/1024))
      else
         Size=$(($(lspv $hdisk|grep TOTAL|cut -f2 -d\(|cut -f1 -d' ')/1024))
      fi
      lscfg -l $hdisk|read hd xx  Description
      printf "%s\t%s\t%s\t%s\t%s\n" "${hdisk}" "${PVID}" "${VG}" "${Size}" "${Description}"
      disk ${hdisk}
   done
   } > "Disklist"
}

function emc_inq
{

   { # EMC INQ Report
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "DEVICE" "VENDOR" "PRODUCT" "REV" "SER NUM" "CAP(kb)"
        /usr/lpp/EMC/Symmetrix/bin/inq.aix64_51|tail +10|sed -e 's/[^a-zA-Z*0-9/]/ /g;s/  */ /g'|while read col1 col2 col3 col4 col5 col6
        do
         printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6"
        done
   } > "EMC INQ Report"
}

function disk
{
   mkdir ${1}
   cd ${1}

   if lspv | grep none | egrep -sw ${1} ;then # sub-SAN disk
      echo "Parent disk" >  "Powerdisk"
      echo $(odmget -qvalue=${1} CuAt|grep name|cut -f2 -d\") >> "Powerdisk"
   elif lspv | grep None | egrep -sw ${1} ;then # Disk not in any VG
      > "${1} is not in any Volume Group"
   else

      if [ ${1%%[0-9]*} = hdiskpower ] ;then
         powermt display dev=$1 > "CLARiiON Info"
      fi
      { # Attributes
         lspv ${1}|sed 's/VG IDENTIFIER/VG IDENTIFIER:/' | while read line
         do
            col1=$(echo ${line}|cut -f1 -d:)
            if echo ${line}|egrep -s ")" ;then
               col2="$(echo ${line}|cut -f2 -d:|cut -f1 -d')'))"
               col3=$(echo ${line}|cut -f2 -d:|cut -f2 -d')'|cut -f1 -d:)
            else
               col2=$(echo ${line}|cut -f2 -d:|cut -f2 -d' ')
               col3=$(echo ${line}|cut -f2 -d:|cut -f3-9 -d' ')
            fi
            col4=$(echo ${line}|cut -f3 -d:)
            printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
         done # while
      } > "Attributes"

      { #Logical Volumes
         printf "%s\t%s\t%s\t%s\t%s\n" "LV NAME" "LPs" "PPs" "DISTRIBUTION" "AMOUNT POINT"
         lspv -l ${1}|egrep -v ':|LV NAME'|while read lv lp pp dis mou
         do
            printf "%s\t%s\t%s\t%s\t%s\n" "$lv" "$lp" "$pp" "$dis" "$mou"
         done
      } > "Logical Volumes"

      { # Physical Partition map
         printf "%s\t%s\t%s\t%s\t%s\t%s\n" "PP RANGE" "STATE" "REGION" "LV NAME" "TYPE" "MOUNT POINT"
         lspv -p ${1}|egrep -v ':|PP RANGE'|while read pp state r1 r2 lv typ mou
         do
            if [[ $r1 = "center" ]] ;then
               range="$r1" mou=$typ typ=$lv lv=$r2
            else
               range="$r1-$r2"
            fi
         printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$pp" "$state" "$range" "$lv" "$typ" "$mou"
         done
      } >  "Physical Partition map"

   fi
   cd ..
}
#######################    Volume Group related    ##########################
function Volume_Groups
{
   mkdir ${0}
   cd ${0}

   { # Volume Groups
      printf "%s\t%s\n" "Volume Group" "Major nr"
      vg=rootvg
      Major=$(ls -l /dev/$vg|awk '{print $5}'|cut -f1 -d,)
      printf "%s\t%s\n" "$vg" "$Major"
      lsvg -o |grep -v rootvg|while read vg
      do
         Major=$(ls -l /dev/$vg|awk '{print $5}'|cut -f1 -d,)
         printf "%s\t%s\n" "$vg" "$Major"
      done
   } > "Volume Groups"

   if [ $(lsvg|wc -l) -gt  $(lsvg -o|wc -l) ] ;then
      { # Volume Groups not Active
         printf "%s\t%s\n" "Volume Group" "Major nr"
         TMPFILE=/tmp/vg$$
         lsvg -o > $TMPFILE
         lsvg |egrep -v -f $TMPFILE |while read vg
         do
            Major=$(ls -l /dev/$vg|awk '{print $5}'|cut -f1 -d,)
            printf "%s\t%s\n" "$vg" "$Major"
         done
         rm $TMPFILE
      } > "Volume Groups not Active"
   fi

   for vg in $(lsvg -o)
   do
      mkdir $vg
      cd $vg

      { # Attributes
         printf "%s\t%s\t%s\t%s\n" "Attribute" "Value" "Attribute" "Value"
         lsvg ${vg}| while read line
         do
            col1=$(echo ${line}|cut -f1 -d:)
            if echo ${line}|egrep -s "LTG" ;then
               col2=$(echo ${line}|cut -f2 -d:|cut -f2-3 -d' ')
               col3=$(echo ${line}|cut -f2 -d:|cut -f4-9 -d' ')
            else
               col2=$(echo ${line}|cut -f2 -d:|cut -f2 -d' ')
               col3=$(echo ${line}|cut -f2 -d:|cut -f3-9 -d' ')
            fi
            col4=$(echo ${line}|cut -f3 -d:)
            printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
         done
      } > "Attributes"

      { # Logical Volumes
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "LV NAME" "TYPE" "LPs" "PPs" "PVs" "LV STATE" "MOUNT POINT"
         lsvg -l ${vg}|egrep -v ':|LV NAME'| while read line
         do
            col1=$(echo ${line}|awk '{print $1}')
            col2=$(echo ${line}|awk '{print $2}')
            col3=$(echo ${line}|awk '{print $3}')
            col4=$(echo ${line}|awk '{print $4}')
            col5=$(echo ${line}|awk '{print $5}')
            col6=$(echo ${line}|awk '{print $6}')
            col7=$(echo ${line}|awk '{print $7}')
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}" "${col5}" "${col6}" "${col7}"
         done
      } > "Logical Volumes"

      { # Physical Volumes
         printf "%s\t%s\t%s\t%s\t%s\n" "PV_NAME" "PV STATE" "TOTAL PPs" "FREE PPs"  "FREE DISTRIBUTION"
         lsvg -p ${vg}|egrep -v ':|PV_NAME'| while read line
         do
            col1=$(echo ${line}|awk '{print $1}')
            col2=$(echo ${line}|awk '{print $2}')
            col3=$(echo ${line}|awk '{print $3}')
            col4=$(echo ${line}|awk '{print $4}')
            col5=$(echo ${line}|awk '{print $5}')
            printf "%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}" "${col5}"
         done
      } > "Physical Volumes"

      cd ..
   done # for vg
   cd ..
}
#####################    Logical Volumes releated    ########################
function LV
{
   mkdir ${1}
   cd ${1}

   { # Attributes
      lslv ${1} | while read line
      do
         col1=$(echo ${line}|cut -f1 -d:)
         col2=$(echo ${line}|cut -f2 -d:|cut -f2 -d' ')
         col3=$(echo ${line}|cut -f2 -d:|cut -f3-9 -d' ')
         col4=$(echo ${line}|cut -f3 -d:)
         printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
      done
   } > "Attributes"

   { # Logical Volume Disk usage
      count=1
      printf "%s\t%s\t%s\t%s\n" "PV" "COPIES" "IN BAND" "DISTRIBUTION"
      lslv -l ${1}|while read col1 col2 col3 col4
      do
         if [ $count -gt 2 ] ;then
           printf "%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}"
         fi
         count=$((count + 1 ))
      done
   } > "Logical Volume Disk usage"

   { # Logical Volume Map
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "LP" "PP1" "PV1" "PP2" "PV2" "PP3" "PV3"
      count=1
      lslv -m ${1} |while read col1 col2 col3 col4 col5 col6 col7
      do
         if [ $count -gt 2 ] ;then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}" "${col5}" "${col6}" "${col7}"
         fi
         count=$((count + 1 ))
      done
   } > "Logical Volume Map"

   cd ..
}

function Logical_Volumes
{
   mkdir ${0}
   cd ${0}

   { # Logical Volumes
      lvs=""
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "LV NAME" "TYPE" "LPs" "PPs" "PVs" "LV STATE" "MOUNT POINT"
      for vg in rootvg $(lsvg -o|egrep -v rootvg)
      do
         lsvg -l ${vg}|egrep -v ':|LV NAME' |while read lv col2 col3 col4 col5 col6 col7
         do
            lvs="$lvs $lv"
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${lv}" "${col2}" "${col3}" "${col4}" "${col5}" "${col6}" "${col7}"
         done
      done
   } > "Logical Volumes"

   for lv in $lvs
   do
      LV $lv
   done

   cd ..
}
########################    Filesystem releated    ########################
function File_Systems
{
   mkdir ${0}
   cd ${0}

   jfsno=$(lsjfs|wc -l)
   if [[ $jfsno -gt 1 ]] ;then
      lsjfs|sed 's/#//' > "jfs filesystems"
   fi

   lsjfs2|sed 's/#//' > "jfs2 filesystems"

   { # Mounted filesystem usage
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Filesystem" "Mounted on" "1024-blocks" "Used" "Free" "%Used" "Iused" "Ifree" "%Iused"
      df -Mkvt|egrep -v ':|Filesystem|/Proc'|while read col1 col2 col3 col4 col5 col6 col7 col8 col9
      do
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${col4}" "${col5}" "${col6}" "${col7}" "${col8}" "${col9}"
      done
   } > "Mounted filesystem usage"

   cd ..
}
########################    Storage usage releated    ######################
function Storage_Usage
{
   mkdir ${0}
   cd ${0}

   { # Storage by VG
      printf "%s\t%s\t%s\t%s\t%s\n" "Volume Group" "Size (GB)" "Allocated (GB)" "Free (GB)" "Free in FS (GB)"
      for vg in rootvg $(lsvg -o|grep -v rootvg)
      do
         PPsize=$(lsvg $vg|grep 'PP SIZE:'|cut -f3 -d:|awk '{print $1}')
         TotPP=$(lsvg $vg|grep 'TOTAL PPs:'|cut -f3 -d:|awk '{print $1}')
         FreePP=$(lsvg $vg|grep 'FREE PPs:'|cut -f3 -d:|awk '{print $1}')
         UsedPP=$(lsvg $vg|grep 'USED PPs:'|cut -f3 -d:|awk '{print $1}')
         fsfree=0
         for fs in $(lsvg -l $vg|egrep 'jfs |jfs2 '|awk '{print $7}')
         do
            [ "$fs" = "N/A" ] && continue
            free=$(df -k $fs |tail -1|awk '{print $3}')
            fsfree=$(($fsfree+$free))
         done
         fsfree=$(($fsfree/1024)) # MB
         fsfree=$(($fsfree/1024)) # GB
         totsize=$(($TotPP*$PPsize/1024))
         totalloc=$(($UsedPP*$PPsize/1024))
         totfree=$(($FreePP*$PPsize/1024))
         printf "%s\t%s\t%s\t%s\t%s\n" "$vg" "$totsize" "$totalloc" "$totfree" "$fsfree"
      done
   } > "Storage by VG"

   { # Storage by disk
      printf "%s\t%s\t%s\t%s\n" "Disk" "Volume Group" "Size (GB)" "Free (GB)"
      for vg in rootvg $(lsvg -o|grep -v rootvg)
      do
         PPsize=$(lsvg $vg|grep 'PP SIZE:'|cut -f3 -d:|awk '{print $1}')
         lsvg -p $vg|egrep -v ':|PV_NAME' | while read pv a TotPP FreePP r
         do
            totsize=$(($TotPP*$PPsize/1024))
            totfree=$(($FreePP*$PPsize/1024))
            printf "%s\t%s\t%s\t%s\n" "$pv" "$vg" "$totsize" "$totfree"
         done
      done
   } >  "Storage by disk"

   { # Paging Space
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Page Space" "Physical Volume" "Volume Group" "Size(GB)" "%Used" "Active" "Auto" "Type" "Chksum"
      lsps -a|egrep -v 'Page Space'|while read col1 col2 col3 col4 col5 col6 col7 col8 col9
         do
            size=$(echo $col4|sed 's/MB//')
            gbsize=$(($size/1024))
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${col1}" "${col2}" "${col3}" "${gbsize}" "${col5}" "${col6}" "${col7}" "${col8}" "${col9}"
         done
   } > "Paging Space"

   { # Dump Settings
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/bin/sysdumpdev -l|while read col1 col2
      do
         printf "%s\t%s\n" "${col1}" "${col2}"
      done
   } > "Dump Settings"

   { # Estimated Dump Size
      printf "%s\t%s\n" "Estimated size(MB)" "Size of dumpdevice(MB)"
      size=$(/usr/bin/sysdumpdev -e|awk -F: '{print $2}')
      esize=$(($size/1048576))
      dumplv=$(sysdumpdev -l |grep primary|cut -f3 -d\/)
      if [ $dumplv = "sysdumpnull" ] ;then
         printf "%s\t%s\n" "No dumpdevice defined" " "
      else
         PPsize=$(lslv $dumplv|egrep 'PP SIZE:'|awk '{print $6}')
         PPs=$(odmget -q"name=$dumplv and attribute=size" CuAt |grep value|cut -f2 -d\")
         ddevsize=$(($PPsize*$PPs))
         printf "%s\t%s\n" "${esize}" "${ddevsize}"
      fi
   } > "Estimated Dump Size"

   { # Dump Devices
      echo "Dump devices\tLV status"
      if [[ $(odmget -q'value="sysdump"' CuAt |wc -l) -eq 0 ]] ;then
         dev=$(/usr/bin/sysdumpdev -l|head -1|awk '{print $2}')
         dev=${dev#/dev/}
         if [ $dev = "sysdumpnull" ] ;then
            status=" - "
         else
            status=$(lslv $dev|awk -F: '/LV STATE/ {print $3}')
         fi
         echo "$dev\t$status"
      else
         for dev in $(odmget -q'value="sysdump"' CuAt |grep name|cut -f2 -d\")
         do
            status=$(lslv $dev|awk -F: '/LV STATE/ {print $3}')
            echo "$dev\t$status"
         done
      fi
   } > "Dump Devices"

   cd ..
}

##############################################################################
##                         Hardware related functions                       ##
##############################################################################
#
function Devices
{
   mkdir ${0}
   cd ${0}

   mkdevicelist

   for device in $(lsdev -C|grep -vw Defined|sort|cut -f1 -d' ')
   do
      device ${device}
   done

   cd ..
}

function mkdevicelist
{
   { # Devicelist
      printf "%s\t%s\t%s\t%s\n" "Device" "State" "Location" "Description"
      lsdev -C | grep -vw Defined | sort | while read Device State Location Description
      do
         case $Location in
            [0-9][0-9]-*) ;;
            *) Description=$Location Location='N/A' ;;
         esac
         printf "%s\t%s\t%s\t%s\n" "$Device" "$State" "$Location" "$Description"
      done
   } > "Devicelist"
}

function device
{
   mkdir ${1}
   cd ${1}

   { # Software Configuration data
      printf "%s\t%s\t%s\t%s\n" "Attribute" "Value" "Description" ""
      lsattr -El $1 | while read Attribute Value Description
      do
         if echo $Description|egrep -s 'True' ;then
            Truth='True'
            Description=${Description%True}
         else
            Truth='False'
            Description=${Description%False}
         fi
         printf "%s\t%s\t%s\t%s\n" "${Attribute}" "${Value}" "${Description}" "${Truth}"
      done
   }> "Software Configuration data"

   lscfg -vpl $1 > "Hardware Configuration data"

   cd ..
}

function EC_and_ROS_levels
{
   mkdir ${0}
   cd ${0}

   { #System firmware
      printf "%s\t%s\t%s\n" "LID Keyword" "Code level"
      lscfg -vp|egrep -p 'System Firmware:'|while read line
      do
         case $line in
            *Level*) LAST=${line##*..}
                     Keyword=$(echo $LAST|cut -f1 -d' ')
                     Code=$(echo $LAST|cut -f2 -d' ')
                     printf "%s\t%s\t%s\n" "$Keyword" "$Code" ;;
         esac
      done
   } > "System Firmware"

   { # EC & ROS Levels
      printf "%s\t%s\t%s\t%s\n" "Device" "Level Description" "EC-ROS level"
      lscfg -vp|egrep -p 'Adapter:'|while read line
      do
         case $line in
            *Level*) Level=${line%%..*} EC_ROS=${line##*..}
                  printf "%s\t%s\t%s\t%s\n" "$Device" "$Level" "$EC_ROS" ;;
            *:)       Device=$(echo $line|awk -F: '{print $1}') ;;
         esac
      done
   } > "Adapter EC and ROS Levels"
   # EC and ROS Levels
   printf "%s\t%s\t%s\t%s\n" "Device" "Level Description" "EC-ROS level" > "EC and ROS Levels"
   lscfg -v|egrep '^  [a-z]|Level'|while read line
   do
      case $line in
         *Level*) Level=${line%%..*} EC_ROS=${line##*..}
                  printf "%s\t%s\t%s\t%s\n" "$Device" "$Level" "$EC_ROS" ;;
         *)       Device=$(echo $line|awk '{print $1}') ;;
      esac
   done > ecar
   sort < ecar >> "EC and ROS Levels"
   rm ecar

   cd ..
}

function Virtual_Product_Data
{
   mkdir ${0}
   cd ${0}

   lscfg -vp > VPD

   cd ..
}
#
##############################################################################
##                         Software related functions                       ##
##############################################################################
#
function    AIX_Maintenance_Levels
{
   mkdir ${0}
   cd ${0}

   TL=$(oslevel -r)
   TS=$(oslevel -s)
   TM="${TL}_AIX_ML"

   { # The AIX Technology level is $TL
     /usr/sbin/instfix -i | grep AIX_ML
     oslevel -rl $TL
   } > "The AIX Technology level is $TL"

   > "The AIX Service Pack level is $TS"

   { # Filesets on a lower level than level ${TL}
     printf "%s\t%s\t%s\t%s\n" "Fileset Name" "Level Installed" "Level Required"
     instfix -icqk "${TM}"|grep ":-:"|while read line
     do
        Fileset=$(echo $line|cut -f2 -d:)
        Installed=$(echo $line|cut -f3 -d:)
        Required=$(echo $line|cut -f4 -d:)
        printf "%s\t%s\t%s\t%s\n" "$Fileset" "$Installed" "$Required"
     done
   } >  "Filesets on a lower level than level ${TL}"

   { # Filesets belonging to level ${TL}
     printf "%s\t%s\t%s\t%s\n" "Fileset Name" "Level Installed" "Level Required"
     instfix -icqk "${TM}"|grep ":=:"|while read line
     do
        Fileset=$(echo $line|cut -f2 -d:)
        Installed=$(echo $line|cut -f3 -d:)
        Required=$(echo $line|cut -f4 -d:)
        printf "%s\t%s\t%s\t%s\n" "$Fileset" "$Installed" "$Required"
     done
   } > "Filesets belonging to level ${TL}"

   { # Filesets belonging to higher level than ${TL}
     printf "%s\t%s\t%s\t%s\n" "Fileset Name" "Level Installed" "Level Required"
     instfix -icqk "${TM}"|grep ":+:"|while read line
     do
        Fileset=$(echo $line|cut -f2 -d:)
        Installed=$(echo $line|cut -f3 -d:)
        Required=$(echo $line|cut -f4 -d:)
        printf "%s\t%s\t%s\t%s\n" "$Fileset" "$Installed" "$Required"
     done
   } > "Filesets belonging to higher level than ${TL}"

   emgr -l > "Emergency fixes" 2>&1

   cd ..
}

function    Installed_LPPs
{
   mkdir ${0}
   cd ${0}

   { # Installed LPPs
      IFS=:
      printf "%s\t%s\t%s\t%s\t%s\n" "Fileset" "Level" "State" "Type" "Description"
      lslpp -cL all | tail +2 | sort | while read Package Fileset Level State1 PTFid State Type Description rest
   do
      if [ "$Fileset" != "" ]
        then
           [ "$Type" = " " ] && Type="F"
           [ "$Type" = "" ] && Type="F"
           case $Type in
               F) Type="Installp";;
               P) Type="Product";;
               C) Type="Component";;
               T) Type="Feature";;
               R) Type="RPM"
           esac
           case $State in
               A) State="Applied";;
               B) State="Broken";;
               C) State="Committed";;
               O) State="Obsolete";;
               ?) State="Inconsistent";;
           esac
           printf "%s\t%s\t%s\t%s\t%s\n" "$Fileset" "$Level" "$State" "$Type" "$Description"
      fi
      done
      IFS=$OIFS
   } > "Installed LPPs"

   cd ..
}

function NIM_Definitions
{
   mkdir ${0}
   cd ${0}

   { # NIM Definitions
      printf "%s\t%s\t%s\n" "Object" "Class" "Type"
      lsnim|while read Object Class Type
      do
           printf "%s\t%s\t%s\n" "$Object" "$Class" "$Type"
      done
   } > "NIM Definitions"

   lsnim|while read Object rest
   do
       nim $Object
   done

   cd ..
}

function nim
{
   mkdir ${1}
   cd ${1}

   { # NIM Object
      printf "%s\t%s\n" "NIM Attribute" "Value"
      IFS='='
      lsnim -l ${1}|grep -v :|while read Attribute Value
      do
         printf "%s\t%s\n" "$Attribute" "$Value"
      done
      IFS=$OIFS
   } > "NIM Object"

   cd ..
}
#
##############################################################################
##                         Network releated functions                       ##
##############################################################################
#
function Network_Interface
{
   mkdir ${0}
   cd ${0}

   { # Interface information
      printf "%s\t%s\t%s\t%s\n" "Interface" "State" "Location" "Type"
      lsdev -Cc if|while read Interface State Location Type
      do
         case $Location in
            [0-9][0-9]-[0-9][0-9]);;
            *) Type="$Location $Type" Location='-';;
         esac
         printf "%s\t%s\t%s\t%s\n" "$Interface" "$State" "$Location" "$Type"
      done
   } > "Interface information"

   { # Running IP configuration - Note AIX 6 differ!!
      case $(oslevel) in
         6*) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Mtu" "Network" "Adress" "ZoneID" "Ipkts" "Ierrs" "Opkts" "Oerrs" "Coll"
             netstat -in -f inet|tail +2|while read  Name Mtu  Network Adress ZoneID Ipkts Ierrs Opkts Oerrs Coll
             do
                if [ "x$Oerrs" = "x" ] ;then
                   Coll=$Opkts Oerrs=$Ierrs Opkts=$Ipkts Ierrs=$ZoneID
                   Ipkts=$Adress ZoneID=' ' Adress=' '
                elif [ "x$Coll" = "x" ] ;then
                   if echo $Network|egrep -s : ;then
                      Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                      Ipkts=$ZoneID  ZoneID=$Adress Adress=' '
                   else
                      Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                      Ipkts=$ZoneID ZoneID=' '
                   fi
                fi
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Name" "$Mtu" "$Network" "$Adress" "$ZoneID" "$Ipkts" "$Ierrs" "$Opkts" "$Oerrs" "$Coll"
             done ;;
            *) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Mtu" "Network" "Adress" "Ipkts" "Ierrs" "Opkts" "Oerrs" "Coll"
               netstat -in -f inet|tail +2|while read  Name Mtu  Network Adress Ipkts Ierrs Opkts Oerrs Coll
               do
               if [ "x$Coll" = "x" ] ;then
                  Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                  Ipkts=$Adress Adress=''
               fi
               printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Name" "$Mtu" "$Network" "$Adress" "$Ipkts" "$Ierrs" "$Opkts" "$Oerrs" "$Coll"
               done ;;
         esac
   } > "Running IP configuration"

   {  # Resolving IP addresses - Note AIX 6 differ!!
      case $(oslevel) in
         6*) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Mtu" "Network" "Adress" "ZoneID" "Ipkts" "Ierrs" "Opkts" "Oerrs" "Coll"
             netstat -i -f inet|tail +2|while read  Name Mtu  Network Adress ZoneID Ipkts Ierrs Opkts Oerrs Coll
              do
              if [ "x$Oerrs" = "x" ] ;then
                 Coll=$Opkts Oerrs=$Ierrs Opkts=$Ipkts Ierrs=$ZoneID
                 Ipkts=$Adress ZoneID=' ' Adress=' '
              elif [ "x$Coll" = "x" ] ;then
                 if echo $Network|egrep -s : ;then
                    Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                    Ipkts=$ZoneID  ZoneID=$Adress Adress=' '
                 else
                    Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                    Ipkts=$ZoneID ZoneID=' '
                 fi
              fi
              printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Name" "$Mtu" "$Network" "$Adress" "$ZoneID" "$Ipkts" "$Ierrs" "$Opkts" "$Oerrs" "$Coll"
              done ;;
            *) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Mtu" "Network" "Adress" "Ipkts" "Ierrs" "Opkts" "Oerrs" "Coll"
               netstat -i -f inet|tail +2|while read  Name Mtu  Network Adress Ipkts Ierrs Opkts Oerrs Coll
               do
               if [ "x$Coll" = "x" ] ;then
                  Coll=$Oerrs Oerrs=$Opkts Opkts=$Ierrs Ierrs=$Ipkts
                  Ipkts=$Adress Adress=''
               fi
               printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Name" "$Mtu" "$Network" "$Adress" "$Ipkts" "$Ierrs" "$Opkts" "$Oerrs" "$Coll"
               done ;;
         esac
      } > "Resolving IP addresses"

   cd ..
}

function Network_Options
{
   mkdir ${0}
   cd ${0}

   { # Network Options
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Parameter Name" "Current Value" "Default Value" "Reboot Value" "Min Value" "Max Value" "Unit" "Type" "Dependent tunables"
      IFS=,
      no -x|sort|while read Parameter Current Default Reboot Min Max Unit Type Dependent
      do
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Parameter" "$Current" "$Default" "$Reboot" "$Min" "$Max" "$Unit" "$Type" "$Dependent"
      done
      IFS=$OIFS
   } > "Network Options"

   cd ..
}

function Network_Configuration_Files
{
   mkdir ${0}
   cd ${0}

   NETFILES="gated.conf hosts hosts.lpd hosts.equiv inetd.conf netsvc.conf ntp.conf rc.net rc.tcpip snmpd.conf telnet.conf ftpusers resolv.conf services"
   { # Network Configuration Files
printf "%s\t%s\n" "File" "Description"
printf "%s\t%s\n" "gated.conf" "Contains configuration information for the gated daemon."
printf "%s\t%s\n" "hosts"       "Defines the Internet Protocol (IP) name and address of the local host and specifies the names and addresses of remote hosts."
printf "%s\t%s\n" "hosts.lpd"   "Specifies remote hosts that can print on the local host."
printf "%s\t%s\n" "hosts.equiv" "Specifies remote systems that can execute commands on the local system."
printf "%s\t%s\n" "inetd.conf" "Defines how the inetd daemon handles Internet service requests."
printf "%s\t%s\n" "netsvc.conf" "Specifies the ordering of certain name resolution services."
printf "%s\t%s\n" "ntp.conf"    "Controls how the Network Time Protocol (NTP) daemon xntpd operates and behaves."
printf "%s\t%s\n" "rc.net"      "Defines host configuration for network interfaces, host name, default gateway, and static routes."
printf "%s\t%s\n" "rc.tcpip"    "File Initializes daemons at each system restart."
printf "%s\t%s\n" "snmpd.conf" "Defines a sample configuration file for the snmpdv1 agent."
printf "%s\t%s\n" "telnet.conf" "Translates a clients terminal-type strings into terminfo file entries."
printf "%s\t%s\n" "ftpusers" "Specifies local user names that cannot be used by remote FTP clients."
printf "%s\t%s\n" "resolv.conf" "Defines Domain Name Protocol (DOMAIN) name-server information for local resolver routines."
printf "%s\t%s\n" "services"    "Defines the sockets and protocols used for Internet services."
   } > "Network Configuration Files"

   for file in $NETFILES
   do
      if [ -f "/etc/${file}" ] ;then
         egrep -v '^;|^#|^$'  "/etc/${file}" > ${file}
      else
         echo "File not found" > ${file}
      fi
   done

   cd ..
}

function Routing
{
   mkdir ${0}
   cd ${0}

   { # Routing table
      printf "%s\t%s\t%s\t%s%s\t%s\t%s\t%s\t%s\n" "Destination" "Gateway" "Flags" "Refs" "Use" "Interface" "Exp" "Groups" "Redirected"
      netstat -rn | tail +5 | grep -v : | while read Destination Gateway Flags Refs Use Interface Exp Groups Redirected
      do
         printf "%s\t%s\t%s\t%s%s\t%s\t%s\t%s\t%s\n" "$Destination" "$Gateway" "$Flags" "$Refs" "$Use" "$If" "$Exp" "$Groups" "$Redirected"
      done
   } > "Routing table"

   { # Routing table(v6)
      printf "%s\t%s\t%s\t%s%s\t%s\t%s\t%s\t%s\n" "Destination" "Gateway" "Flags" "Refs" "Use" "Interface" "Exp" "Groups" "Redirected"
      netstat -rn | tail +5 | grep : | grep -v "Route" |  while read Destination Gateway Flags Refs Use Interface Exp Groups Redirected
      do
         printf "%s\t%s\t%s\t%s%s\t%s\t%s\t%s\t%s\n" "$Destination" "$Gateway" "$Flags" "$Refs" "$Use" "$If" "$Exp" "$Groups" "$Redirected"
      done
   } > "Routing table(v6)"

   { # Routing table(ODM)
      printf "%s\t%s\t%s\t%s\t%s\n" "Net/Host" "Hopcount" "Netmask" "Destination" "Gateway"
      lsattr -HEl inet0 | grep route|while read r odmentry R
      do
         if [ $(echo "$odmentry"|sed 's/[^,]//g'|wc -c) -eq 6 ] ;then #default route
            odmentry=$(echo "$odmentry"|sed 's/,,/,,,,,,/')
         elif echo "$odmentry"|egrep -s '-netmask,' ;then
            odmentry=$(echo "$odmentry"|sed 's/-netmask,//')
         fi
         odmentry=$(echo "$odmentry"|sed 's/,,,,//')
         odmentry=$(echo "$odmentry"|sed 's/-hopcount,//')
         echo  "$odmentry"|sed 's/,/    /g'
      done
   } > "Routing table(ODM)"

   cd ..
}

function DNS
{
   mkdir ${0}
   cd ${0}

   { # resolv.conf
      if [ -f "/etc/${file}" ] ;then
         egrep -v '^;|^#|^$'  "/etc/${file}" > ${file}
      else
         echo "File not found" > ${file}
      fi
   } > "resolv.conf"

   { # netsvc.conf
      if [ -f "/etc/${file}" ] ;then
         egrep -v '^;|^#|^$'  "/etc/${file}" > ${file}
      else
         echo "File not found" > ${file}
      fi
   } > "netsvc.conf"

   { # DNS lookup check
       lsdev -Cc  if | grep -w Available | grep -v lo0 | cut -f1 -d' ' | while read interface
       do
          netaddress=$(lsattr -El $interface -a netaddr|cut -f2 -d' ')
          if [ "x$netaddress" = "x" ] ;then # living networkdevice without IP adress
             print "No IP address configured for Available interface: $interface"
          elif ! hostnew $netaddress >/dev/null 2>&1 ;then
             print "The IP address $netaddress configured on $interface is not known on the nameserver"
          else
             hostnew $netaddress | read x y name rest
             hostnew $name
             hostnew $name | read reversename x reverseaddress rest
             if [ "$netaddress" = "$reverseaddress" ] ; then
                print "Reverse name lookup testet and OK"
             else
                print "Reverse Name lookup failed."
                print "$netaddress is translated in $name"
                print "$name is translated back in $reverseaddress"
             fi
          fi
       done
   } > "DNS lookup check"

   { # NSORDER variable
      if [ -z "$NSORDER" ]
      then
         print "NSORDER variable not set"
      else
         print "NSORDER: $NSORDER"
       fi
   } > "NSORDER variable"

   cd ..
}

function NFS
{
   mkdir ${0}
   cd ${0}

   { # NFS exports
      printf "%s\t%s\n" "Filesystems" "Export parameters"
      [ -f  /etc/exports ] && cat /etc/exports|while read Filesystems Export
      do
         printf "%s\t%s\n" "$Filesystems" "$Export"
      done
   } > "NFS exports"

   /usr/etc/lsnfsmnt|sed 's/[   ][      ]*/     /g' > "NFS mounts"

   { # NFS Tuning
      printf "%s\t%s\n" "Tuning parameter" "Value"
      if [ -x /usr/sbin/nfso ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            nfso -a|sed 's/[        ][  ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read nfso
            do
            nfso_tp=$nfso" ="
            nfso_value=$(nfso -a|grep -w "$nfso_tp"|awk '{print $3}')
         printf "%s\t%s\n" "$nfso" "$nfso_value"
         done
         fi
      fi
   } > "NFS Tuning"

   { # NFS Tuning - next boot
      printf "\t%s\t%s\n" "Tuning parameter" "Value"
      if [ -x /usr/sbin/nfso ] ;then
         if [ -s /etc/tunables/nextboot ] ;then
            grep -p nfso /etc/tunables/nextboot|egrep -v : |sed 's/[        ][  ]*//g'|sed 's/=/        /'|sed 's/"//g'|awk '{print $1}'|while read nfso
        do
        nfso_tp=$nfso" ="
        nfso_value=$(grep -p nfso /etc/tunables/nextboot|egrep -v :|grep -w "$nfso_tp"|awk '{print $3}')
        printf "%s\t%s\n" "$nfso" "$nfso_value"
        done
         fi
      fi
   } > "NFS Tuning - next boot"

   cd ..
}
#
##############################################################################
##                           User releated functions                        ##
##############################################################################
#
function user_details
{
   mkdir "${1}"
   cd "${1}"

   { # Details
      printf "\t%s\t%s\n" "User Attribute" "Value"
      IFS='='
      lsuser -f "${1}"|egrep -v ':'|while read Attribute Value
      do
         printf "%s\t%s\n" "$Attribute" "$Value"
      done
      IFS=$OIFS
   } > "Details"

   cd ..
}

function User
{
   mkdir ${0}
   cd ${0}

   { # User list
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Username" "uid" "Real Name" "login" "rlogin" "Locked" "From System" "Session Time"
      for usr in $(lsuser -a registry ALL|grep "=files"|cut -f1 -d' '|sort)
      do
         gecos="$(lsuser -a gecos ${usr}|cut -f2 -d=\")"
         [ "x$gecos" = "x" ] && gecos="Anonymous"
         time_last_login=''
         tty_last_login=''
         host_last_login=''
         lsuser -a id account_locked login rlogin time_last_login tty_last_login host_last_login $usr |read id rest
         eval "$rest"
         fromhost="$host_last_login"
         [[ "$time_last_login" = vty? ]] && fromhost="Console"
         [[ "$time_last_login" = lft? ]] && fromhost="Screen"
         [[ "$time_last_login" = tty? ]] && fromhost="TTY"
         [ "x$fromhost" = "x" ] && fromhost="N/A"
         if [ "x$time_last_login" = "x" ] ;then
            time_last_login="Never"
         else
            time_last_login=$(chardate $time_last_login)
         fi
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${usr}" "${id}" "${gecos}" "${login}" "${rlogin}" "${account_locked}" "${fromhost}" "${time_last_login}"
         user_details "$usr"
      done
   } > "User list"

   cd ..
}

function Group
{
   mkdir ${0}
   cd ${0}

   { # Group list
      printf "\t%s\t%s\t%s\n" "Group" "gid" "Members"
      IFS=:
      lsgroup -c -a id users ALL|grep -v '#'|sort|while read Group gid Members
      do
         printf "\t%s\t%s\t%s\n" "$Group" "$gid" "$Members"
      done
      IFS=$OIFS
   } > "Group list"

   cd ..
}

function Sudo
{
   mkdir ${0}
   cd ${0}

   { # Sudo list
     printf "%s\t%s\n" "User/Group" "Privileges"
      if [ -f /etc/sudoers ] ;then
        egrep -v '^;|^#|^$' /etc/sudoers|while read UG Privileges
        do
            printf "%s\t%s\n" "$UG" "$Privileges"
        done
      else
            printf "%s\t%s\n" "SUDO" "is not installed"
      fi
   } > "Sudo list"

   cd ..
}
#
##############################################################################
##                           "High Level" functions                         ##
##############################################################################
#
function VCS
{
   mkdir ${0}
   cd ${0}
     VCS_information
   cd ..
}

function VIO
{
   mkdir ${0}
   cd ${0}
     VIO_System
     VIO_Disks
     VIO_Network
     VIO_Devices
     VIO_Mapping
   cd ..
}

function System
{
   mkdir ${0}
   cd ${0}
   General_Information
   LPAR_information
   System_Configuration
   System_Tuning
   cd ..
}

function Storage
{
   mkdir ${0}
   cd ${0}
   Disks
   Volume_Groups
   Logical_Volumes
   File_Systems
   Storage_Usage
   cd ..
}

function Hardware
{
   mkdir ${0}
   cd ${0}
   Devices
   EC_and_ROS_levels
   Virtual_Product_Data
   cd ..
}

function Software
{
   mkdir ${0}
   cd ${0}
   AIX_Maintenance_Levels
   Installed_LPPs
   #Only if NIM server:
   if lslpp -l|egrep -s nim.master ;then
      NIM_Definitions
   fi
   cd ..
}

function Network
{
   mkdir ${0}
   cd ${0}
   Network_Interface
   Network_Options
   Network_Configuration_Files
   Routing
   DNS
   NFS
   cd ..
}

function Users
{
   mkdir ${0}
   cd ${0}
   User
   Group
   Sudo
   cd ..
}
#
##############################################################################
##                                    MAIN                                  ##
##############################################################################
#
cd $OUTROOT
FREE=$(df -m $OUTROOT|tail -1|awk '{print $3}'|cut -f1 -d.)
if [ $FREE -le 100 ]; then # less than 100 MB left do not write
   exit 1
fi
[ ! -d $OUTROOT ] && error "$OUTROOT not found !"
echo "Starting on $HOST at $TODAY.............." >&2
OUTDIR=$OUTROOT/$HOST/$TODAY/
[ -d $OUTDIR ] && rm -r $OUTDIR # We are redoing today
mkdir -p $OUTDIR
cd $OUTDIR
[ ! -z $ISVIOserver ] && time VIO
[ ! -z $ISVCSserver ] && time VCS
time System
time Storage
time Hardware
time Software
time Network
time Users
echo "Finished $HOST at $TODAY.............." >&2

