#!/bin/ksh
# Script which automatically create a DR profile on a system in the opposite data center.
# Create new vfchosts for the profile on VIO servers.
# Map the new vfchosts to FCS adapters.
# Start LPAR with DR profile in normal mode.
# Script created and tested by ShyamKumar Chauhan
#
if [ `hostname` = gpfs01 ]
then
        HMC=HMC1
elif [ `hostname` = gpfs02 ]
then
        HMC=HMC2
else
        echo "This script is not executed from the correct server"
        exit
fi

echo "Do we have a disaster type situation [No]/YES?"
read anwser
case $anwser in
      NO|No|no) anwser="no";;
      YES) anwser="YES";;
      *) anwser="no";;
esac
if [ "$anwser" = "no" ]
then
        echo "Mistake we have not disaster situation."
        exit
else
        echo "Please enter system which datacenter has problems [DC1]/DC2"
        read DC
        if [ $DC = DC1 ]
        then
                echo "Which system in DC1 need DR failover of LPARs [Server-8205-E6C-SN06XXXXR]?"
                echo "Please enter Power system ID:"
                echo "Server-8205-E6C-SN06XXXXR"
                echo "Server-9179-MHD-SN65XXXXE"
                echo "Server-9179-MHD-SN06XXXXT"
                read ORISYS
                if [ $ORISYS = Server-9179-MHD-SN65XXXXE -o $ORISYS = Server-8205-E6C-SN06XXXXR ]
                then
                        DRSYS=Server-9179-MHD-SN65XXXXE
                        DRVIOA=HMC2-VIO01
                        DRVIOB=HMC2-VIO02
                elif [ $ORISYS = Server-9179-MHD-SN06XXXXT ]
                then
                        DRSYS=Server-9179-MHD-SN06XXXXT
                        DRVIOA=HMC2-VIO05
                        DRVIOB=HMC2-VIO06
                fi
                LASTDUMP=`ls -lrt /Nimfs/HMC_lssyscfg/$HMC/$ORISYS.* |grep -v LPAR |tail -1 |awk '{print $9}'`
                DRFILE=/Nimfs/HMC_lssyscfg/$HMC/$ORISYS.LPAR.lst
                for ORILPAR in `cat $DRFILE |awk '{print $1}'`
                do
                        ORIPROF=`grep ^name=$ORILPAR $LASTDUMP`
                        ORIVIOA=`echo $ORIPROF |cut -d\/ -f34`
                        ORIVIOB=`echo $ORIPROF |cut -d\/ -f40`
                        if [ $ORISYS = Server-8205-E6C-SN06XXXXR ]
                        then
                                DRPROFT=`echo $ORIPROF |sed -e s/"$ORILPAR"/"$ORILPAR-DRXYZ"/g |sed -e s/"$ORIVIOA"/"$DRVIOA"/g |sed -e s/"$ORIVIOB"/"$DRVIOB"/g |sed -e s/lpar_name="$ORILPAR-DRXYZ"/profile_name="$ORILPAR"/g`
                                DRPROF=`echo $DRPROFT |sed -e s/"20\/client\/3\/"/"20\/client\/2\/"/g |sed -e s/"21\/client\/4\/"/"21\/client\/3\/"/g`
                        else
                                DRPROF=`echo $ORIPROF |sed -e s/"$ORILPAR"/"$ORILPAR-DRXYZ"/g |sed -e s/"$ORIVIOA"/"$DRVIOA"/g |sed -e s/"$ORIVIOB"/"$DRVIOB"/g |sed -e s/lpar_name="$ORILPAR-DRXYZ"/profile_name="$ORILPAR"/g`
                        fi
#                       DRPROFM=`echo $DRPROF |cut -d, -f1-2,4,6-8,13,15-23,29-34,37-40,42`
                        DRPROFM=`echo $DRPROF |cut -d, -f1,2,4-23,26-48`
                        SLOT=`echo $ORIPROF |cut -d\/ -f35`
                        PING=`ping -c 3 $ORILPAR |grep "packet loss" |awk '{print $7}' |cut -d% -f1`
                        ACTIVE=`ssh $HMC -l hscroot lssyscfg -r lpar -m $ORISYS --filter ""lpar_names=$ORILPAR"" -F name:state |cut -d: -f2`
                        echo "$ORILPAR is $ACTIVE"
                        if [ $PING -eq 0 ]
                        then
                                echo "$ORILPAR still reply upon ping. Please check if $ORILPAR is realy down."
                        elif [ "$ACTIVE" = "Running" ]
                        then
                                echo "$ORILPAR still have a status of $ACTIVE. Please check if $ORILPAR is realy down."
                        else
                                ssh $HMC -l hscroot "mksyscfg -r lpar -m $DRSYS -i '$DRPROFM'"
                                echo ""
                                sleep 2
                                ssh $HMC -l hscroot "chhwres -r virtualio -m $DRSYS -o a -p $DRVIOA --rsubtype fc -s $SLOT -a "adapter_type=server,remote_lpar_name=$ORILPAR-DRXYZ,remote_slot_num=20""
                                echo ""
                                sleep 2
                                ssh $HMC -l hscroot "chhwres -r virtualio -m $DRSYS -o a -p $DRVIOB --rsubtype fc -s $SLOT -a "adapter_type=server,remote_lpar_name=$ORILPAR-DRXYZ,remote_slot_num=21""
                                echo ""
                                sleep 2
                        fi
                done
                ACTIVEDR=`ssh $HMC -l hscroot lssyscfg -r lpar -m $DRSYS -F name:state |grep "\-DRXYZ" |wc -l`
                if [ $ACTIVEDR = 0 ]
                then
                        echo "It seems that no disaster profiles have been created on $DRSYS"
                else
                        ssh $DRVIOA /fcs_load_distribute.ksh
                        echo ""
                        sleep 2
                        ssh $DRVIOB /fcs_load_distribute.ksh
                        echo ""
                        sleep 2
                        for DRLPAR in `ssh $HMC -l hscroot lssyscfg -r lpar -m $DRSYS -F name:state |grep "\-DRXYZ" |cut -d: -f1`
                        do
                                ORILPAR=`echo $DRLPAR |sed -e s/-DRXYZ//g`
                                PING=`ping -c 3 $ORILPAR |grep "packet loss" |awk '{print $7}' |cut -d% -f1`
                                ACTIVE=`ssh $HMC -l hscroot lssyscfg -r lpar -m $ORISYS --filter ""lpar_names=$ORILPAR"" -F name:state |cut -d: -f2`
                                echo "$ORILPAR is $ACTIVE"
                                if [ $PING -eq 0 ]
                                then
                                        echo "$ORILPAR still reply upon ping. Please check if $ORILPAR is realy down."
                                elif [ "$ACTIVE" = "Running" ]
                                then
                                        echo "$ORILPAR still have a status of $ACTIVE. Please check if $ORILPAR is realy down."
                                else
                                        ssh $HMC -l hscroot "chsysstate -r lpar -m $DRSYS -o on -f $ORILPAR -b normal -n $ORILPAR-DRXYZ"
                                        echo "Starting $ORILPAR-DRXYZ on $DRSYS"
                                        sleep 2
                                fi
                        done
                fi
        fi
        if [ $DC = DC2 ]
        then
                ORISYS=Server-9179-MHD-SN65XXXXE
                echo "Which system in DC2 need DR failover of LPARs [Server-9179-MHD-SN65XXXXE]?"
                echo "Please enter Power system ID:"
                echo "Server-9179-MHD-SN65XXXXE"
                echo "Server-9179-MHD-SN06XXXXT"
                read ORISYS
                if [ $ORISYS = Server-9179-MHD-SN65XXXXE ]
                then
                        DRSYS=Server-9179-MHD-SN65XXXXE
                        DRVIOA=HMC1-VIO01
                        DRVIOB=HMC1-VIO02
                elif [ $ORISYS = Server-9179-MHD-SN06XXXXT ]
                then
                        DRSYS=Server-9179-MHD-SN06XXXXT
                        DRVIOA=HMC1-VIO05
                        DRVIOB=HMC1-VIO06
                fi
                LASTDUMP=`ls -lrt /Nimfs/HMC_lssyscfg/$HMC/$ORISYS.* |grep -v LPAR |tail -1 |awk '{print $9}'`
                DRFILE=/Nimfs/HMC_lssyscfg/$HMC/$ORISYS.LPAR.lst
                for ORILPAR in `cat $DRFILE |awk '{print $1}'`
                do
                        ORIPROF=`grep ^name=$ORILPAR $LASTDUMP`
                        ORIVIOA=`echo $ORIPROF |cut -d\/ -f34`
                        ORIVIOB=`echo $ORIPROF |cut -d\/ -f40`
                        DRPROF=`echo $ORIPROF |sed -e s/"$ORILPAR"/"$ORILPAR-DRXYZ"/g |sed -e s/"$ORIVIOA"/"$DRVIOA"/g |sed -e s/"$ORIVIOB"/"$DRVIOB"/g |sed -e s/lpar_name="$ORILPAR-DRXYZ"/profile_name="$ORILPAR"/g`
#                       DRPROFM=`echo $DRPROF |cut -d, -f1-2,4,6-8,13,15-23,29-34,37-40,42`
                        DRPROFM=`echo $DRPROF |cut -d, -f1,2,4-23,26-48`
                        SLOT=`echo $ORIPROF |cut -d\/ -f35`
                        PING=`ping -c 3 $ORILPAR |grep "packet loss" |awk '{print $7}' |cut -d% -f1`
                        ACTIVE=`ssh $HMC -l hscroot lssyscfg -r lpar -m $ORISYS --filter ""lpar_names=$ORILPAR"" -F name:state |cut -d: -f2`
                        echo "$ORILPAR is $ACTIVE"
                        if [ $PING -eq 0 ]
                        then
                                echo "$ORILPAR still reply upon ping. Please check if $ORILPAR is realy down."
                        elif [ "$ACTIVE" = "Running" ]
                        then
                                echo "$ORILPAR still have a status of $ACTIVE. Please check if $ORILPAR is realy down."
                        else
                                ssh $HMC -l hscroot "mksyscfg -r lpar -m $DRSYS -i '$DRPROFM'"
                                echo ""
                                sleep 2
                                ssh $HMC -l hscroot "chhwres -r virtualio -m $DRSYS -o a -p $DRVIOA --rsubtype fc -s $SLOT -a "adapter_type=server,remote_lpar_name=$ORILPAR-DRXYZ,remote_slot_num=20""
                                echo ""
                                sleep 2
                                ssh $HMC -l hscroot "chhwres -r virtualio -m $DRSYS -o a -p $DRVIOB --rsubtype fc -s $SLOT -a "adapter_type=server,remote_lpar_name=$ORILPAR-DRXYZ,remote_slot_num=21""
                                echo ""
                                sleep 2
                        fi
                done
                ACTIVEDR=`ssh $HMC -l hscroot lssyscfg -r lpar -m $DRSYS -F name:state |grep "\-DRXYZ" |wc -l`
                if [ $ACTIVEDR = 0 ]
                then
                        echo "It seems that no disaster profiles have been created on $DRSYS"
                else
                        ssh $DRVIOA /fcs_load_distribute.ksh
                        echo ""
                        sleep 2
                        ssh $DRVIOB /fcs_load_distribute.ksh
                        echo ""
                        sleep 2
                        for DRLPAR in `ssh $HMC -l hscroot lssyscfg -r lpar -m $DRSYS -F name:state |grep "\-DRXYZ" |cut -d: -f1`
                        do
                                ORILPAR=`echo $DRLPAR |sed -e s/-DRXYZ//g`
                                PING=`ping -c 3 $ORILPAR |grep "packet loss" |awk '{print $7}' |cut -d% -f1`
                                ACTIVE=`ssh $HMC -l hscroot lssyscfg -r lpar -m $ORISYS --filter ""lpar_names=$ORILPAR"" -F name:state |cut -d: -f2`
                                echo "$ORILPAR is $ACTIVE"
                                if [ $PING -eq 0 ]
                                then
                                        echo "$ORILPAR still reply upon ping. Please check if $ORILPAR is realy down."
                                elif [ "$ACTIVE" = "Running" ]
                                then
                                        echo "$ORILPAR still have a status of $ACTIVE. Please check if $ORILPAR is realy down."
                                else
                                        ssh $HMC -l hscroot "chsysstate -r lpar -m $DRSYS -o on -f $ORILPAR -b normal -n $ORILPAR-DRXYZ"
                                        echo "Starting $ORILPAR-DRXYZ on $DRSYS"
                                        sleep 2
                                fi
                        done
                fi
        fi
fi
