#!/bin/sh

INSTALL_DIR=$1
LOG_FILE=$2
NAME=$3
LOCK_FILENAME=$4
IOTCORE_BACKOFF=$5
IOTCORE_QOS=$6
shift 6
CMD=$*

#
# Is Debian, Ubuntu?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep Ubuntu`
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
# Patch Device Name as directed...
#
DEVICE_NAME=${NAME}
if [[ $NAME == *"__none__"* ]]; then
   DEVICE_NAME=`echo $NAME | sed 's/__none__//g'`
   NAME=""
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

#
# Setup env vars for edge-impulse-linux/runner AWS IoTCore Topics and Config
#
EI_TOPIC_ROOT="/edgeimpulse/device"
EI_DEVICE_NAME=`echo $DEVICE_NAME | sed 's/ /_/g' | sed "s/'//g"`
export EI_OUTPUT_BACKOFF_COUNT=$IOTCORE_BACKOFF
export EI_IOTCORE_QOS=$IOTCORE_QOS
export EI_INFERENCE_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/inference/output"
export EI_METRICS_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/model/metrics"
export EI_COMMAND_INPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/command/input"
export EI_COMMAND_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/command/output"

#
# Patch Ubuntu 22+ with pipewire and systemd changes
#
if [ ! -z "${IS_UBUNTU}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Debug
echo "EI: Launch: Name: ${NAME} Device: ${DEVICE_NAME} CMD: ${CMD}"
if [ ! -z "${IS_UBUNTU}" ]; then
    echo "EI: Launch(ubuntu): XDG_RUNTIME_DIR=/run/user/$UID"
    echo "EI: Launch(ubuntu): DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Launch!
export EI_SERIAL_RUNNER_CMD="${CMD}"
TS_CMD="./parser.sh ${LOG_FILE}"

PARSER_INSTALL_DIR="/home/${GREENGRASS_SERVICEUSER}/parser"
echo "Launching ${TS_CMD} in directory: ${PARSER_INSTALL_DIR} with Serial Runner: ${EI_SERIAL_RUNNER_CMD}..."
cd ${PARSER_INSTALL_DIR}
${TS_CMD}
STATUS=$?
echo "EI: ${CMD} has exited with status: ${STATUS}"

echo "EI: launch.sh removing the lockfile..."
rm -f ${LOCK_FILENAME} 2>&1 1>/dev/null

echo "EI: launch.sh exiting with status ${STATUS}"
exit ${STATUS}