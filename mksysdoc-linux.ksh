#!/bin/ksh
#---------------------------------------------------------------------------
#
#         Filename:  mksysdoc-linux.ksh
#
#      Description:  Collect the SyetmDocumentation for ALL LINUX Servers
#
#           Author:  ShyamKumar Chauhan
#
#
#       Example root's crontab entry:
#      0 6 * * 6 /usr/local/bin/mksysdoc-linux.ksh > /dev/null 2>&1
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
set -a Month "" Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
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
        echo "`lltstat -nvv|tail -n +2|head -9`"
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
function General_Information_Linux
{
   mkdir ${0}
   cd ${0}

   {  # Server Model Info
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/sbin/dmidecode | grep Product|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Server Model Info"

   {  # CPU Model Info
      printf "%s\t%s\n" "Attribute" "Value"
      cat /proc/cpuinfo|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "CPU Model Info"

   {  # Linux Base Version
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/bin/lsb_release -a|column -t|while read line
      do
        col1=$(echo ${line}|cut -d: -f1|sed 's/ //g')
        col2=$(echo ${line}|cut -d: -f2-|sed 's/ //g')
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Linux Base Version"

   {  # Memory Info
      printf "%s\t%s%1c%s\n" "Attribute" "Value"
      cat /proc/meminfo|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|awk '{print $2}')
        col3=$(echo ${line}|awk '{print $3}')
        printf "%s\t%s%1c%s\n" "$col1" "$col2" "$col3"
      done
   } > "Memory Info"

   { # System Information
      printf "%s\t%s\n" "Attribute" "Value"
      /sbin/dmidecode -t system|head -13|tail -n +6|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "System Information"

   { # OS Information
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/local/bin/hwlist.sh --system|head -9|tail -n +4|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "OS Information"
   cd ..
}

function System_Configuration_Linux
{
   mkdir ${0}
   cd ${0}

  EtcFiles="aliases ftpusers passwd group inittab profile hosts syslog.conf sysctl.conf nsswitch.conf services mtab"
  {  # etc configuration files
      printf "%s\t%s\n" "File" "Description"
      printf "%s\t%s\n" "aliases" "Contains alias definitions for the sendmail command."
      printf "%s\t%s\n" "ftpusers" "who can ftp connect, what parts of the system are accessible etc."
      printf "%s\t%s\n" "passwd" "Lists local users. "
      printf "%s\t%s\n" "group" "The /etc/passwd file contains basic user attributes."
      printf "%s\t%s\n" "inittab" "Controls the initialization process."
      printf "%s\t%s\n" "profile" "Sets the user environment at login time."
      printf "%s\t%s\n" "hosts" "A list of machines that can be contacted "
      printf "%s\t%s\n" "syslog.conf" "Controls output of the syslogd daemon."
      printf "%s\t%s\n" "sysctl.conf" "Configured kernel variables"
      printf "%s\t%s\n" "nsswitch.conf" "Order in which to contact the name resolvers"
      printf "%s\t%s\n" "services" "Connections accepted by this machine (open ports)."
      printf "%s\t%s\n" "mtab" "Currently mounted file systems."
   } > "etc configuration files"

   for file in $EtcFiles
   do
      if [ -f "/etc/${file}" ] ;then
         egrep -v '^;|^#|^$'  "/etc/${file}" > ${file}
      else
         echo "File not found" > ${file}
      fi
   done

   { #crontab
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Minute" "Hour" "DayOfMonth" "Month" "Weekday" "Command"
      for user in `ls -l /var/spool/cron|awk '{print $9}'|tail -n +2`
      do
      printf "%s\n" "$user"
      crontab - $user -ll|egrep -v '^;|^#|^$'|while read Minute Hour DayOfMonth Month Weekday Command
      do
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$Minute" "$Hour" "$DayOfMonth" "$Month" "$Weekday" "$Command"
      done
      done
   } > "crontab"

   uname -a|grep el7
   result=$?
   if [ $result -eq 0 ]; then
   {  # Service_Runlevel
      printf "%s\t%s\n" "Service" "State"
      systemctl list-unit-files|grep -iv unit|while read line
      do
        col1=$(echo ${line}|awk '{print $1}')
        col2=$(echo ${line}|awk '{print $2}')
      printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Service_Runlevel"

   else
   {  # Service_Runlevel
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Service" "0" "1" "2" "3" "4" "5" "6"
      chkconfig --list|awk '/xinetd based services/ {exit} {print}'|while read line
      do
        col1=$(echo ${line}|awk '{print $1}')
        col2=$(echo ${line}|awk '{print $2}')
        col3=$(echo ${line}|awk '{print $3}')
        col4=$(echo ${line}|awk '{print $4}')
        col5=$(echo ${line}|awk '{print $5}')
        col6=$(echo ${line}|awk '{print $6}')
        col7=$(echo ${line}|awk '{print $7}')
        col8=$(echo ${line}|awk '{print $8}')
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7" "$col8"
      done
   } > "Service_Runlevel"

   {  # xinetd_based_services
      printf "%s\t%s\n" "Service" "Status"
      chkconfig --list|grep -A50 'xinetd based services'|grep -v based|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2)
      printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "xinetd_based_services"
   fi

   {  # System_ulimit
      printf "%s\t%s\t%s\n" "Attribute" "Unit" "Value"
      bash -c "ulimit -a"|while read line
      do
        col1=$(echo ${line}|sed 's/ //g'|awk -F"[()]" '{print $1}')
        col2=$(echo ${line}|sed 's/ //g'|awk -F"[()]" '{print $2}')
        col3=$(echo ${line}|sed 's/ //g'|awk -F"[()]" '{print $3}')
        printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3"
      done
   } > "System_ulimit"

   {  # Kernel_Variables
      printf "%s\t%s\n" "Attribute" "Value"
      /sbin/sysctl -a 2> /dev/null | sort -u|while read line
      do
        col1=$(echo ${line}|awk '{print $1}')
        col2=$(echo ${line}|cut -d "=" -f2)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Kernel_Variables"

   cd ..
}

##############################################################################
##                         Storage releated functions                       ##
##############################################################################
#
function LVM_Information
{
   mkdir ${0}
   cd ${0}

   { # Volume Group
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "VG" "Attr" "VPerms" "VSize" "VFree" "Ext" "#Ext" "Free" "#PV" "#LV" "Fmt" "VG UUID"
      /sbin/vgs -o vg_name,vg_attr,vg_permissions,vg_size,vg_free,vg_extent_size,vg_extent_count,vg_free_count,pv_count,lv_count,vg_fmt,vg_uuid|tail -n +2|while read col1 col2 col3 col4 col5 col6 col7 col8 col9 col10 col11 col12
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7" "$col8" "$col9" "$col10" "$col11" "$col12"
      done
   } > "Volume Group"

   { # Logical Volume
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "LV" "Path" "VG" "LSize" "Attr" "KMaj" "KMin" "LV UUID" "Type" "CTime"
      /sbin/lvs -o lv_name,lv_path,vg_name,lv_size,lv_attr,lv_kernel_major,lv_kernel_minor,lv_uuid,segtype,lv_time|tail -n +2|while read col1 col2 col3 col4 col5 col6 col7 col8 col9 col10
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7" "$col8" "$col9" "$col10"
      done
   } > "Logical Volume"

   { # Physical Volume
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "PV" "Attr" "PSize" "Used" "PFree" "DevSize" "Total PE" "Allocated PE" "PV UUID"
      /sbin/pvs -o pv_name,pv_attr,pv_size,pv_used_,pv_free,dev_size,pv_pe_count,pv_pe_alloc_count,pv_uuid|tail -n +2|while read col1 col2 col3 col4 col5 col6 col7 col8 col9
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7" "$col8" "$col9"
      done
   } > "Physical Volume"

   cd ..
}

function FileSystems
{
   mkdir ${0}
   cd ${0}

   { # File_Systems
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Filesystem" "Type" "Size" "Used" "Avail" "Use%" "Mounted on"
      df -hT|grep -v Filesystem|while read col1 col2 col3 col4 col5 col6 col7
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7"
      done
   } > "File_Systems"

   cd ..
}

function Disk_Linux
{
   mkdir ${0}
   cd ${0}

   { # SCSI Disks
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "scsi_host" "Type" "Vendor" "Model" " " "Revision" "Device"
      lsscsi |grep disk|while read col1 col2 col3 col4 col5 col6 col7
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7"
      done
   } > "SCSI Disks"

   { # Block Devices
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Name" "Maj:Min" "RM" "Size" "RO" "Type" "Mountpoint"
      lsblk|tail -n +2|while read col1 col2 col3 col4 col5 col6 col7
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7"
      done
   } > "Block Devices"

      pidof multipathd > /dev/null
      if [[ $? -eq 0 ]];
      then
      multipath -ll > "Multipath Configuration"
      fi
      fdisk -l > "Disk Partition Table"

   cd ..
}

##############################################################################
##                         Hardware releated functions                      ##
##############################################################################
#
function System_Details
{
   mkdir ${0}
   cd ${0}

   { # Operating System Details
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/local/bin/hwlist.sh --system|head -9|tail -n +4|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Operating System Details"

   { # System Hardware Details
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/local/bin/hwlist.sh --system|tail -n +13|head -4|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "System Hardware Details"

   { # System Motherboard Details
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/local/bin/hwlist.sh --system|head -23|tail -n +20|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "System Motherboard Details"

   { # System BIOS Details
      printf "%s\t%s\n" "Attribute" "Value"
      /usr/local/bin/hwlist.sh --system|tail -3|while read line
      do
        col1=$(echo ${line}|cut -d: -f1)
        col2=$(echo ${line}|cut -d: -f2-)
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "System BIOS Details"

   cd ..
}

function Storage_Device_Details
{
   mkdir ${0}
   cd ${0}

    /usr/local/bin/hwlist.sh --disk > "Disk Details"
    cd ..
}

function Network_Details
{
   mkdir ${0}
   cd ${0}

      /usr/local/bin/hwlist.sh --network > "Network Details"
    cd ..
}

function Processor_Details
{
   mkdir ${0}
   cd ${0}

      /usr/local/bin/hwlist.sh --cpu > "Processor Details"
    cd ..
}

function Memory_Details
{
   mkdir ${0}
   cd ${0}

    /usr/local/bin/hwlist.sh --memory > "Memory Details"
    cd ..
}

function System_Health
{
   mkdir ${0}
   cd ${0}

    /usr/local/bin/hwlist.sh --health > "System Health"
    cd ..
}

##############################################################################
##                         Network releated functions                       ##
##############################################################################
#
function Network_Interface_Linux
{
   mkdir ${0}
   cd ${0}

   { # Interface_information
      printf "%s\t%s\n" "Interface" "State"
      /sbin/ip link show|grep mtu|while read line
      do
      col1=$(echo ${line}|awk '{print $2}'|tr -d ':')
      col2=$(echo ${line}|awk '{print $9}')
        printf "%s\t%s\n" "$col1" "$col2"
      done
   } > "Interface_information"

   { # Running IP Configuration
      printf "%s\t%s\t%s\n" "Interface" "MTU" "Address/Mask"
      /sbin/ip addr show|grep mtu|while read line
      do
      col1=$(echo ${line}|awk '{print $2}'|tr -d ':')
      col2=$(echo ${line}|awk '{print $5}')
      done
      /sbin/ip addr show|grep -w inet|while read line
      do
      col3=$(echo ${line}|awk '{print $2}')
      done
        printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3"
   } > "Running IP Configuration"

   { # Routing Table
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Destination" "Gateway" "Genmask" "Flags" "MSS" "Window" "irtt" "Iface"
      netstat -rn | tail -n +3|while read col1 col2 col3 col4 col5 col6 col7 col8
      do
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$col1" "$col2" "$col3" "$col4" "$col5" "$col6" "$col7" "$col8"
      done
   } > "Routing Table"

   cd ..
}

##############################################################################
##                           User releated functions                        ##
##############################################################################
#
function user_details_linux
{
   mkdir "${1}"
   cd "${1}"

   { # Details_Linux
      printf "%s\t%s\n" "User Attribute" "Value"
      IFS=':'
      lslogins "${1}"|awk '/Running processes/ {exit} {print}'|while read Attribute Value
      do
         printf "%s\t%s\n" "$Attribute" "$Value"
      done
   } > "Details_Linux"

   cd ..
}

function User_Linux
{
   mkdir ${0}
   cd ${0}

   { # User list Linux
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "USER" "UID" "PROC" "PWD-LOCK" "PWD-DENY" "GECOS"
      lslogins|tail -n +2|while read line
      do
           user=$(echo ${line}|awk '{print $2}')
           uid=$(echo ${line}|awk '{print $1}')
           proc=$(echo ${line}|awk '{print $3}')
           pwdlock=$(echo ${line}|awk '{print $4}')
           pwddeny=$(echo ${line}|awk '{print $5}')
           gecos=$(echo ${line}|awk '{print $6$7$8$9$10$11$12$13}'|tr -d ':,0-9')
         printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$user" "$uid" "$proc" "$pwdlock" "$pwddeny" "$gecos"
         user_details_linux "$user"
      done
   } > "User list Linux"

   cd ..
}

function Group_Linux
{
   mkdir ${0}
   cd ${0}

   { # Group list Linux
      printf "%s\t%s\t%s\n" "Group" "gid" "Members"
      cut -d':' -f1,3,4 --output-delimiter=' ' /etc/group|while read line
      do
             group=$(echo ${line}|awk '{print $1}')
             gid=$(echo ${line}|awk '{print $2}')
             members=$(echo ${line}|awk '{print $3}')
         printf "%s\t%s\t%s\n" "$group" "$gid" "$members"
      done
   } > "Group list Linux"

   cd ..
}

function Sudo_Linux
{
   mkdir ${0}
   cd ${0}

   { # Sudo list Linux
     printf "%s\t%s\n" "User/Group" "Privileges"
      if [ -f /etc/sudoers ] ;then
        egrep -v '^;|^#|^$' /etc/sudoers|while read UG Privileges
        do
            printf "%s\t%s\n" "$UG" "$Privileges"
        done
      else
            printf "%s\t%s\n" "SUDO" "is not installed"
      fi
   } > "Sudo list Linux"

   cd ..
}
#
##############################################################################
##                         Software releated functions                      ##
##############################################################################
#
function Installed_RPMS
{
   mkdir ${0}
   cd ${0}

   { # Installed_RPMS
      printf "%s\t%s\t%s\n" "RPM" "Version" "Provider"
      rpm -qa --queryformat '%-50{NAME} %-50{VERSION} %{VENDOR}\n'|sort -d -f|while read line
      do
      col1=$(echo ${line}|awk '{print $1}')
      col2=$(echo ${line}|awk '{print $2}')
      col3=$(echo ${line}|awk '{print $3$4$5}')
      printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3"
      done
   } > "Installed_RPMS"

   cd ..
}

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

function System
{
   mkdir ${0}
   cd ${0}
   General_Information_Linux
   System_Configuration_Linux
   cd ..
}

function Storage
{
   mkdir ${0}
   cd ${0}
   Disk_Linux
   LVM_Information
   FileSystems
   cd ..
}

function Hardware
{
   mkdir ${0}
   cd ${0}
   System_Details
   Storage_Device_Details
   Network_Details
   Processor_Details
   Memory_Details
   System_Health
   cd ..
}

function Software
{
   mkdir ${0}
   cd ${0}
   Installed_RPMS
   cd ..
}

function Network
{
   mkdir ${0}
   cd ${0}
   Network_Interface_Linux
   cd ..
}

function Users
{
   mkdir ${0}
   cd ${0}
   User_Linux
   Group_Linux
   Sudo_Linux
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
[ ! -z $ISVCSserver ] && time VCS
time System
time Storage
time Hardware
time Software
time Network
time Users
echo "Finished $HOST at $TODAY.............." >&2
