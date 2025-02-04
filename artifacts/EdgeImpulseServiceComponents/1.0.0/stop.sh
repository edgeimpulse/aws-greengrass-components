#!/bin/sh

#
# DEBUG
# set -x

#
# GG Component Deployment Command line params
#
INSTALL_DIR="$1"
LOCK_FILENAME="$2"

#
# Just remove the lock file...
#
rm -f ${LOCK_FILENAME} 2>&1 1>/dev/null