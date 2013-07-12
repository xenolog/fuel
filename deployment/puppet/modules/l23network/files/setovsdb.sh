#!/bin/bash
INTERNAL_ADDR=$1
if [ -z "$(grep remote=ptcp /usr/share/openvswitch/scripts/ovs-ctl)" ] ; then 
	sed -i "/--remote=punix/a \\\tset\ \"\$\@\"\ --remote=ptcp:6644:${INTERNAL_ADDR}" /usr/share/openvswitch/scripts/ovs-ctl
fi
