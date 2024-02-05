#!/bin/bash

timestamp=`date +%m%d%y%H%M`
mydate=`date +m%d%y`
datadir=/opt/sonatype-work/nexus3
configdir=/opt/nexus
backupdir=/backups
logdir=/backups/logs
notify=gopala.gabbita@gmail.com
logret=30 #log returns of a time series
archret=7

####### Decide on the env for a few variables ###########

if  [`hostname` = nexus-dev ]; then
    myhost=nexus
    healthurl=**/ping
    mybucket= #create aws bucket##
    logfile=/backups/logs/nexus.backup.$timestamp.log
    errlogfile=/backups/logs/nexus.backup.$timestamp.log
elif [`hostname` = nexus-prod]; then
    myhost=nexusiq-prod
    healthurl=https://***/ping
    mybucket= ##s3 bucket create ##
    logfile=/backups/logs/nexus.backup.$timestamp.log
    errlogfile=/backups/logs/nexus.backup.$timestamp.err.log
else 
    echo " no match hosting, exiting"
    exit 1
 fi 

 #################functions###############

 #

f_stop ()
{
sudo systemctl stop nexus 
sleep 30 
pid=`ps aux | grep nexus | grep '.jar server' | grep -vE '(stop|grep)' | awk '{print $2}'`

if [! -z $pid ] ; then # If pid is not empty then the service failed to stop. Exit and report
    echo "Looks like service failed to stop. please check " | tee -a $errlogfile 
    echo " sending alert" #send alert 
    mailx -a $errlogfile -s "`hostname` - Backup Failure, please check logfile" $notify < /dev/null
    exit 1 
fi 
 }

 #

 f_backup ()
 {
mkdir -p $backupdir/$mydate 
cd $datadir ; tar -cf $backupdir/$mydate/sonatype-work.$myhost.$timestamp.tar

if [$? != 0]; then 
    echo " Backup issues - please check - `date`" | tee -a $errlogfile
    echo "sending alert" # send alert 
    mailx -a $errorlogfile -s "`hostname` - Backup Failure, Please check logfile" $notify < /dev/null
    exit 1 
else
    echo " Tar backup looks to have completed ok - `date`" | tee -a $logfile 
fi 
 }

f_backupfiles ()
{
cp -p $configdir/current/system $backupdir/$mydate
cp -p $configdir/current/lib $backupdir/$mydate.lib
cp -p $configdir/current/etc $backupdir/$mydate.etc
cp -p $configdir/current/bin $backupdir/$mydate.bin
cp -p $configdir/current/public $backupdir/$mydate.bin

if [$? != 0]; then 
    echo "Backup issues for config files - Please check - `date`" | tee -a $errlogfile
    echo "sending alert" # send alert 
    mailx -a $errlogfile -s "`hostname` - Backup Failure, please check logfile" $notify < /dev/null 
    exit 1 
else
    echo " Copy backup looks to have completed ok - `date` " | tee -a $logfile
fi 

}

f_startup ()
{
sudo systemctl start nexus 
sleep 15
pid=`ps aux | grep nexus | grep '.jar server' | grep -vE '(stop|grep)' | awk '{print $2}'`
        
if [! -z $pid ] ; then 
    echo "PID:$pid -Service is up - `date` " | tee -a $logfile 
else
    echo "Startup problem, please check - `date`" | tee -a $errlogfile
    echo "sending alert"
    mailx -a $errlogfile -s "`hostname` - Backup Failure, please check logfile" $notify < /dev.null
    exit 1 
fi 

}

f_s3() #Backup to S3 bucket for access should EBS backup volume go away for any reason 
{
echo "Copying backup files to S3 $mybucket"
aws s3 cp $backupdir/$mydate s3://$mybucket/backups/$mydate --recursive --exclude "*" --include "*.tar" --include "*.config.yml" --include "*.p12"
if [ $? !=0 ] ; then 
    echo "Copy issues for Nexus Server `hostname` to S3- Please check - `date`" | tee -a $errlogfile 
    echo "sending alert" # send alert 
    mailx -a $errlogfile -s "`hostname` - Backup Failue, please check logfile" $notify < /dev/null 
    exit 1 
else
    echo "Copy to S3 looks to have completed ok - `date`" | tee -a $logfile 
fi 
}

f_clean ()
{
find $backupdir -mindpth 1 -xautofs -xdev -type d -mtime +$archret -exec rm -rf {} + >/dev/null 2>&1
}
############################## Run functions. If any steps fail on alert will be sent ###################
f_stop && f_backup && f_backupfiles && f_startup && f_s3 && f_clean

##end
