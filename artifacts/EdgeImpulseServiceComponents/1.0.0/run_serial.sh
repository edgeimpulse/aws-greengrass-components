#!/bin/sh

#
# DEBUG
# set -x

#
# GG Component Deployment Command line params
#
INSTALL_DIR="$1"
DEVICE_NAME="$2"
SLEEP_TIME_SEC="$3"
LOCK_FILENAME="$4"
IOTCORE_BACKOFF="$5"
IOTCORE_QOS="$6"
EI_BINDIR="$7"

EXISTS="2"

#
# Is Debian, Ubuntu, Yocto?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep -E '(Ubuntu|RT)'`
export YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip|qc|qli|frdm)'`
IS_AVNET_RZBOARD=`uname -a | grep -E '(rzboard)'`
IS_FRDM_BOARD=`uname -a | grep -E '(frdm)'`
IS_QC_BOARD=`uname -a | grep -E '(qli)'`

# Rationalize for those yocto instances whose 'uname -a' does not reveal that its yocto
if [ -z "${YOCTO}" ]; then
    if [ -z "${IS_UBUNTU}" ] && [ -z "${IS_DEBIAN}" ]; then
        YOCTO_CHECK=`uname -a | cut -d ' ' -f 3 | grep "v"`  # look for version in release version (i.e. "v8" in scarthgap)
        if [ ! -z "${YOCTO_CHECK}" ]; then
            echo "Override check: On Yocto Platform: ${YOCTO_CHECK}."
            export YOCTO="yocto"
        else 
            echo "WARNING: Unable to ascertain whether we are on Yocto or not: check: ${YOCTO_CHECK} yocto: ${YOCTO} all: ${ALL}"
        fi
    else 
        echo "On either Ubuntu or Debian. OK"
    fi
else
    echo "On Yocto platform: ${YOCTO}"
fi

#
# Binary directory
#
BIN_DIR=${EI_BINDIR}
if [ "${EI_BINDIR}" = "/usr/local/bin" ]; then
    # default specified. So check for Yocto and adjust...
    if [ ! -z "${YOCTO}" ]; then
        if [ -f /usr/bin/edge-impulse-linux-runner ] ; then
            # Yocto placed binaries in /usr/bin
            BIN_DIR="/usr/bin"
        fi
    fi
fi

# Ensure our path is set correctly... 
export PATH=${BIN_DIR}:${PATH}

# map GST_ARGS from placeholder
if [ "${GST_ARGS}" = "__none__" ]; then
    GST_ARGS=""
fi

# Greengrass Configuration
export GREENGRASS_SERVICEUSER="ggc_user"
export GREENGRASS_SERVICEGROUP="ggc_group"
export HOME_DIR=/home/${GREENGRASS_SERVICEUSER}
export GG_LITE="NO"
if [ -f /etc/greengrass/config.d/greengrass-lite.yaml ]; then
    export GG_LITE="YES"
    export GREENGRASS_SERVICEUSER="gg_component"
    export GREENGRASS_SERVICEGROUP="gg_component"
    export HOME_DIR=/home/${GREENGRASS_SERVICEUSER}   
fi

# Make our device name and lock file unique for our specific host
HOSTID=`cat /var/lib/dbus/machine-id`
if [ ! -z "${HOSTID}" ]; then
    echo "EI: Customizing launch with hostid: ${HOSTID}..."
    DEVICE_NAME=${DEVICE_NAME}_${HOSTID}
    LOCK_FILENAME=${LOCK_FILENAME}_${DEVICE_NAME}
else
    echo "EI: hostid binary not found. Not customizing with a HOSTID (POTENTIAL DUPLICATION WARNING)"
fi

announce_versions() {
    echo "EI: GG Install Directory: ${INSTALL_DIR}"
    echo "EI: Device Name: ${DEVICE_NAME}"
    echo "EI: Sleep Time (sec): ${SLEEP_TIME_SEC}"
    echo "EI: Device Name: ${DEVICE_NAME}"
    echo "EI: Lockfile: ${LOCK_FILENAME}"
}

kill_proc() {
    NAME="$1"
    if [ ! -z "${NAME}" ]; then
        PID_CMD="ps -ef"
        if [ ! -z "${YOCTO}" ]; then
           PID_CMD="ps"
        fi
        PID=`${PID_CMD} | grep ${NAME}| grep EdgeImpulse | awk '{print $2}'`
        if [ ! -z "${PID}" ]; then
        echo "EI: Killing ${NAME} with PID: ${PID}..."
        kill ${PID}
        else 
        echo "EI: Process ${NAME} is not running (OK)..."
        fi
    else
        echo "EI: kill_proc(): no parameter provided. Ignoring..."
    fi
}

launch_serial() {
    # Build the full parameters
    BIN="${BIN_DIR}/edge-impulse-run-impulse"
    FULL_PARAMS="$LOCK_FILENAME ${IOTCORE_BACKOFF} ${IOTCORE_QOS} $BIN"

    # launch!
    echo "EI: Starting EI Serial service: $BIN..."
    ${INSTALL_DIR}/launch_serial.sh $INSTALL_DIR ${LOCK_FILENAME}-$$.log $DEVICE_NAME $FULL_PARAMS 2>&1 1> ${LOCK_FILENAME}-$$.log &
}

set_lockfile() {
    touch ${LOCK_FILENAME} 2>&1 1> /dev/null
    lockfile_exists
}

remove_lockfile() {
    rm ${LOCK_FILENAME} 2>&1 1> /dev/null
}

lockfile_exists() {
    EXISTS="2"
    if [ -f ${LOCK_FILENAME} ]; then
       EXISTS="1"
    fi
}

kill_all() {
    kill_proc "parser.sh"
}

reset() {
    echo "EI: Killing EI services..."
    kill_all
    echo "EI: Removing lockfile..."
    remove_lockfile
    echo "EI: Reset completed."
}

do_wait() {
    lockfile_exists
    while [ "${EXISTS}" = "1" ]; do
        sleep ${SLEEP_TIME_SEC}
        lockfile_exists
    done
    echo "EI: main loop do_wait() has exited. Closing down..."
    reset
}

launch_services() {
    lockfile_exists
    if [ "${EXISTS}" = "1" ]; then
        echo "EI: EI Services already launched... OK"
        exit 0 
    else
        echo "EI: Starting EI Serial Service launch..."
        set_lockfile $*
        launch_serial
        echo "EI: Entering main wait loop..."
        do_wait
    fi
}

main() {
    announce_versions
    reset
    launch_services
}

main
echo "EI Services exiting normally."
exit 0