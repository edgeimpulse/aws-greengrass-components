#!/bin/bash

#
# DEBUG
# set -x

#
# GG Component Deployment Command line params
#
INSTALL_DIR="$1"
DEVICE_NAME="$2"
EI_LAUNCH="$3"
SLEEP_TIME_SEC="$4"
LOCK_FILENAME="$5"
GST_ARGS="$6"
IOTCORE_BACKOFF="$7"
IOTCORE_QOS="$8"
EI_BINDIR="$9"
EI_SM_SECRET_ID="${10}"
EI_SM_SECRET_NAME="${11}"
EI_POLL_SLEEPTIME_MS="${12}"
EI_LOCAL_MODEL_FILE="${13}"
SHUTDOWN_BEHAVIOR="${14}"
PUBLISH_INFERENCE_IMAGE="${15}"
shift 15
EI_PARAMS="$*"

EXISTS="2"
YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip)'`

# Greengrass service user
GREENGRASS_SERVICEUSER="ggc_user"

# kvssink compile 
export SRC_DIR=/home/${GREENGRASS_SERVICEUSER}
if [ -z "${GST_PLUGIN_PATH}" ]; then
    export GST_PLUGIN_PATH="${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build"
else
    export GST_PLUGIN_PATH="${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build:${GST_PLUGIN_PATH}"
fi
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/open-source/local/lib"

#
# Binary directory
#
BIN_DIR=${EI_BINDIR}

#
# Default directory is different on YOCTO
#
if [ "${EI_BINDIR}" = "/usr/local/bin" ]; then
    # default specified. So check for Yocto and adjust...
    if [ ! -z "${YOCTO}" ]; then
        # Yocto places binaries in /usr/bin
        BIN_DIR="/usr/bin"
    fi
fi

# Ensure our path is set correctly... 
export PATH=${BIN_DIR}:${PATH}

# map GST_ARGS from placeholder
if [ "${GST_ARGS}" = "__none__" ]; then
    GST_ARGS=""
fi

# Make our device name and lock file unique for our specific host
MAC_ID=`cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address | sed 's/://g'`
if [ ! -z "${MAC_ID}" ]; then
    echo "EI: Customizing launch with hostid: ${MAC_ID}..."
    DEVICE_NAME=${DEVICE_NAME}_${MAC_ID}
    LOCK_FILENAME=${LOCK_FILENAME}_${DEVICE_NAME}
else
    echo "EI: hostid binary not found. Not customizing with a HOSTID (POTENTIAL DUPLICATION WARNING)"
fi

announce_versions() {
    echo "EI: GG Install Directory: ${INSTALL_DIR}"
    echo "EI: Sleep Time (sec): ${SLEEP_TIME_SEC}"
    echo "EI: Command Poll Sleep Time (ms): ${EI_POLL_SLEEPTIME_MS}"
    echo "EI: Device Name: ${DEVICE_NAME}"
    echo "EI: Lockfile: ${LOCK_FILENAME}"
    echo "EI: Params: ${EI_PARAMS}"
    echo "EI: GST Args: ${GST_ARGS}"
    echo "EI: Shutdown behavior: ${SHUTDOWN_BEHAVIOR}"
    echo "EI: Publish Inference Image to IoCore: ${PUBLISH_INFERENCE_IMAGE}"
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

launch_linux() {
    # Build the full parameters
    BIN="${BIN_DIR}/edge-impulse-linux"
    FULL_PARAMS="${IOTCORE_BACKOFF} ${IOTCORE_QOS} ${EI_SM_SECRET_ID} ${EI_SM_SECRET_NAME} ${EI_POLL_SLEEPTIME_MS} ${EI_LOCAL_MODEL_FILE} ${SHUTDOWN_BEHAVIOR}  ${PUBLISH_INFERENCE_IMAGE} ${BIN} ${EI_PARAMS}"

    # Build out the optional GST Launch args parameter if present
    export GST_LAUNCH_ARGS=""
    if [ ! -z "${GST_ARGS}" ]; then
        UNWRAPPED_ARGS=`echo ${GST_ARGS} | sed 's/:/ /g'`
        export GST_LAUNCH_ARGS="${UNWRAPPED_ARGS}"
    fi

    # launch!
    echo "EI: Starting EI Linux service: $BIN  with args: ${FULL_PARAMS}..."

    # FIXME: We have to work around "edge-impulse-linux" as it manually requests a device name... so DEVICE_NAME is first arg and we'll use that to set the dev name... 
    ${INSTALL_DIR}/launch.sh $DEVICE_NAME $LOCK_FILENAME $FULL_PARAMS 2>&1 1> ${LOCK_FILENAME}-$$.log &
}

launch_runner() {
    # Build the full parameters
    BIN="${BIN_DIR}/edge-impulse-linux-runner"
    FULL_PARAMS="${IOTCORE_BACKOFF} ${IOTCORE_QOS} ${EI_SM_SECRET_ID} ${EI_SM_SECRET_NAME} ${EI_POLL_SLEEPTIME_MS} ${EI_LOCAL_MODEL_FILE} ${SHUTDOWN_BEHAVIOR} ${PUBLISH_INFERENCE_IMAGE} ${BIN} ${EI_PARAMS}"

    # Build out the optional GST Launch args parameter if present
    export GST_LAUNCH_ARGS=""
    if [ ! -z "${GST_ARGS}" ]; then
        UNWRAPPED_ARGS=`echo ${GST_ARGS} | sed 's/:/ /g'`
        export GST_LAUNCH_ARGS="${UNWRAPPED_ARGS}"
    fi

    # launch!
    echo "EI: Starting EI Runner service: $BIN  with args: ${FULL_PARAMS}..."

    # FIXME: __none__ prepends DEVICE_NAME so that we dont have to work around setting a device name like we do with "edge-impulse-linux" in launch_linux() above... 
    ${INSTALL_DIR}/launch.sh __none__$DEVICE_NAME $LOCK_FILENAME $FULL_PARAMS 2>&1 1> ${LOCK_FILENAME}-$$.log &
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
    kill_proc "launch.sh"
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
        echo "EI: Starting EI Service launch..."
        set_lockfile $*
        if [ "${EI_LAUNCH}" = "linux" ]; then
            launch_linux
        elif [ "${EI_LAUNCH}" = "runner" ]; then
            launch_runner
        else
            echo "EI ERROR: Launch config: ${EI_LAUNCH} not recognized. Aborting..."
            reset
            exit 1
        fi
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