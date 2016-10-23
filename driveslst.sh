#!/bin/bash

readarray lst < /var/db/cp/vdslst.lst

for ((i=0; i<${#lst[*]}; i++))
    do
	s=${lst[$i]}
	vdsname=`echo "$s" | awk '{ print $1 }'`
	hvname=`echo "$s" | awk '{ print $2 }'`
	hvip=`echo "$s" | awk '{ print $3 }'`
	echo vdsname=$vdsname hvip=$hvip
	ssh root@$hvip "cat /etc/xen/auto/$vdsname" | grep disk
    done
