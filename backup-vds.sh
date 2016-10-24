#!/bin/bash

function backupworker {
    vdsname=$1
    hvname=$2
    hvip=$3
    pid=$BASHPID
    echo `date +"%Y-%m-%d %H:%M:%S"` pid=$pid vdsname=$vdsname hvname=$hvname hvip=$hvip | tee /var/log/backups/worker-$pid.log
    if [ ! -d /backup/vds-images/$hvname ]; then mkdir /backup/vds-images/$hvname; fi
    part=`ssh root@$hvip "cat /etc/xen/auto/$vdsname"  | grep disk | awk -F '[:,]' '{print $2 }'`
    partsize=`ssh root@$hvip "lvs --units b" | grep $vdsname | awk '{ print $4 }'`
    ssh root@$hvip "lvcreate -L20G -s -n lv-snapdata-nl $part" >> /var/log/backups/worker-$pid.log
    ssh root@$hvip "dd if=/dev/vg/lv-snapdata-nl bs=1M | gzip" | gunzip | \
	dd of=/backup/vds-images/$hvname/$vdsname.img bs=1M >> /var/log/backups/worker-$pid.log 2>&1
    ssh root@$hvip "lvremove -f /dev/vg/lv-snapdata-nl" >> /var/log/backups/worker-$pid.log
    imgsize=`du -b /backup/vds-images/$hvname/$vdsname.img | awk '{ print $1 }'`
    if [[ "$partsize" != "$imgsize"B ]]; then
        echo size of $vdsname does not match | tee /var/log/backups/worker-$pid.log
        echo size of $vdsname does not match | mail -s "backup failed" dalex@king-servers.com, notify@king-support.com
    fi
    echo `date +"%Y-%m-%d %H:%M:%S"` vdsname=$vdsname Compressing image >> /var/log/backups/worker-$pid.log
    gzip -f -7 /backup/vds-images/$hvname/$vdsname.img >> /var/log/backups/worker-$pid.log
    echo `date +"%Y-%m-%d %H:%M:%S"` vdsname=$vdsname Done ! >> /var/log/backups/worker-$pid.log
    cat /var/log/backups/worker-$pid.log >> /var/log/backups/common.log
    rm -f /var/log/backups/worker-$pid.log
    echo "update vdslist set status=2 where vdsname='$vdsname'" | mysql vdsbackup
}

MaxWorkers=6

cat /dev/null >/var/log/backups/common.log

find /backup/vds-images -type f -mtime +30 -delete

freesps=`df / | grep "/" | awk '{ print $4 }'`
if [ $freesps -le 1000000000 ]; then
    echo not enough free space on `hostname -s` | mail -s "backup failed" dalex@king-servers.com, notify@king-support.com
    exit 1
    else echo ok
fi

readarray lst < /var/db/cp/vdslst.lst
echo "delete from vdslist" | mysql vdsbackup

for ((i=0; i<${#lst[*]}; i++))
    do
        s=${lst[$i]}
        vdsname=`echo "$s" | awk '{ print $1 }'`
        hvname=`echo "$s" | awk '{ print $2 }'`
        hvip=`echo "$s" | awk '{ print $3 }'`
        echo vdsname=$vdsname hvip=$hvip
        echo "insert vdslist set vdsname='$vdsname', hvname='$hvname', ip='$hvip', status=0" | mysql vdsbackup
    done

c=`echo "select count(*) from vdslist where status=0" | mysql -s vdsbackup`
while ((c>0))
    do
        w=`echo "select count(*) from vdslist where status=1" | mysql -s vdsbackup`
        if ((w<$MaxWorkers)); then
            vdsname=`echo "select vdsname from vdslist where status=0 and hvname not in \
                (select hvname from vdslist where status=1) limit 1" | mysql -s vdsbackup`
            hvname=`echo "select hvname from vdslist where vdsname='$vdsname' limit 1" | mysql -s vdsbackup`
            hvip=`echo "select ip from vdslist where vdsname='$vdsname' limit 1" | mysql -s vdsbackup`
            echo "update vdslist set status=1 where vdsname='$vdsname'" | mysql vdsbackup
            if [ "$vdsname" ]
        	then
        	    backupworker $vdsname $hvname $hvip & 
            fi
            c=`echo "select count(*) from vdslist where status=0" | mysql -s vdsbackup`
        fi
    sleep 120
    echo `date +"%Y-%m-%d %H:%M:%S"` left - $c
    done
