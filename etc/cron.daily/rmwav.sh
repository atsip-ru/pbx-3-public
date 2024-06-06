#!/bin/sh

FIND="/usr/bin/find"
DIR_FILES="/var/spool/asterisk/monitor/"
PARAM="-type f -mtime +180"
DEL="| xargs rm -rfv {} \;"
eval $FIND $DIR_FILES $PARAM $DEL

