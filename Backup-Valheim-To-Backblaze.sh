#!/bin/bash

#get the current date
#BACKUPTIME=`date +%b-%d-%y`
BACKUPTIME=`date -u +%FT%H%MZ`

#Define Folders
SOURCEFOLDER=/home/steam/.config/unity3d/IronGate/Valheim/worlds
VHBACKUPFOLDER=/home/steam/worldbackups
CLOUDMOUNT=/home/steam/b2mount

#Define save file
DESTINATION=$VHBACKUPFOLDER/backup-$BACKUPTIME.tar.gz

#Define  BackBlaze-dependent variables
B2URL=https://s3.<DATACENTER>.backblazeb2.com
BUCKET=<BUCKETNAME>

TESTFILE=$CLOUDMOUNT/B2IsMounted.txt

#Create a backup file using the current date in it's name
tar -cpzf $DESTINATION $SOURCEFOLDER -P

#Set permissions
chmod 750 $DESTINATION

#Mount BackBlaze
s3fs -o url=$B2URL -o use_path_request_style -o bucket=$BUCKET -o passwd_file=/etc/passwd-s3fs $CLOUDMOUNT

#If the B2IsMounted.txt file is present, copy the map backup file to B2
#then delete files older than 30 days, and delete them;
#then  unmount the s3fs filesystem
if test -f "$TESTFILE"; then
    cp $DESTINATION $CLOUDMOUNT &&
    touch $TESTFILE &&
    find $CLOUDMOUNT -mtime +15 -type f -delete &&
    sleep 5 &&
    umount $CLOUDMOUNT
fi

#find and delete files older than 10 days

find $VHBACKUPFOLDER -mtime +10 -type f -delete
