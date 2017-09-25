#!/bin/sh
ip route add default via $GW
mount -a
exit 0
