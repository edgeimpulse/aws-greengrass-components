#!/bin/sh

NAME=$1
LOCK_FILENAME=$2
IOTCORE_BACKOFF=$3
IOTCORE_QOS=$4
EI_SM_SECRET_ID=$5
EM_SM_SECRET_NAME=$6
IOTCORE_SLEEPTIME_MS=$7
EI_LOCAL_MODEL_FILE=$8
SHUTDOWN_BEHAVIOR=$9
PUBLISH_INFERENCE_IMAGE="${10}"
ENABLE_CACHE_TO_FILE="${11}"
CACHE_FILE_DIRECTORY="${12}"
ENABLE_THRESHOLD_LIMIT="${13}"
METRICS_SLEEPTIME_MS="${14}"
DEFAULT_THRESHOLD="${15}"
THRESHOLD_CRITERIA="${16}"
ENABLE_CACHE_TO_S3="${17}"
S3_BUCKET="${18}"
shift 18
CMD=$*

if [ ! -z "${GST_LAUNCH_ARGS}" ]; then
   echo "GST Launch Args: ${GST_LAUNCH_ARGS}"
fi

#
# Is Debian, Ubuntu, Yocto?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep -E '(Ubuntu|RT)'`
export YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip|qc|qli|frdm|5.15)'`
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

# Greengrass Configuration
export GREENGRASS_SERVICEUSER="ggc_user"
export GREENGRASS_SERVICEGROUP="ggc_group"
export HOME_DIR=/home/${GREENGRASS_SERVICEUSER}
export GG_LITE="NO"
if [ -f /etc/greengrass/config.d/greengrass-lite.yaml ]; then
    export GG_LITE="YES"
    export GREENGRASS_SERVICEUSER="ggcore"
    export GREENGRASS_SERVICEGROUP="ggcore"
    export TARGET_USER=${GREENGRASS_SERVICEUSER}
    export TARGET_GROUP=${GREENGRASS_SERVICEGROUP}
    export HOME_DIR=/home/${GREENGRASS_SERVICEUSER}
    export TARGET_DIR=${HOME_DIR}
fi

# kvssink compile 
export HOME_DIR=/home/${GREENGRASS_SERVICEUSER}
if [ -z "${GST_PLUGIN_PATH}" ]; then
    export GST_PLUGIN_PATH="${HOME_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build"
else
    export GST_PLUGIN_PATH="${HOME_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build:${GST_PLUGIN_PATH}"
fi
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${HOME_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/open-source/local/lib"

#
# Patch Device Name as directed...
#
DEVICE_NAME=${NAME}
if [[ $NAME == *"__none__"* ]]; then
   DEVICE_NAME=`echo $NAME | sed 's/__none__//g'`
   if [[ $CMD == *"--monitor true"* ]]; then
      NAME=${DEVICE_NAME}
   else
      NAME=""
   fi
fi

# map EI_LOCAL_MODEL_FILE from placeholder
if [ "${EI_LOCAL_MODEL_FILE}" = "__none__" ]; then
    EI_LOCAL_MODEL_FILE=""
fi

# map EI_SHUTDOWN_BEHAVIOR from placeholder
if [ "${SHUTDOWN_BEHAVIOR}" != "__none__" ]; then
    export EI_SHUTDOWN_BEHAVIOR="${SHUTDOWN_BEHAVIOR}"
fi

#
# Setup env vars for edge-impulse-linux/runner AWS IoTCore Topics and Config
#
EI_TOPIC_ROOT="/edgeimpulse/device"
EI_DEVICE_NAME=`echo $DEVICE_NAME | sed 's/ /_/g' | sed "s/'//g" | sed 's/__none__//g'`
export EI_OUTPUT_BACKOFF_COUNT=$IOTCORE_BACKOFF
export EI_IOTCORE_QOS=$IOTCORE_QOS
export EI_IOTCORE_POLL_SLEEP_TIME_MS=$IOTCORE_SLEEPTIME_MS
export EI_INFERENCE_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/inference/output"
export EI_METRICS_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/model/metrics"
export EI_COMMAND_INPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/command/input"
export EI_COMMAND_OUTPUT_TOPIC=${EI_TOPIC_ROOT}"/"${EI_DEVICE_NAME}"/command/output"

#
# SecretsManager configuration
#
export EI_AWS_SECRET_ID=${EI_SM_SECRET_ID}
export EI_AWS_SECRET_NAME=${EM_SM_SECRET_NAME}

#
# Option to publish inference image along with inference (default is "no")
#
if [ "${PUBLISH_INFERENCE_IMAGE}" = "yes" ]; then
    export EI_INCLUDE_BASE64_IMAGE="yes"
else
    export EI_INCLUDE_BASE64_IMAGE="no"
fi

#
# Option to cache inference + image to file (default is "no")
#
if [ "${ENABLE_CACHE_TO_FILE}" = "yes" ]; then
    export EI_ENABLE_WRITE_TO_FILE="yes"
else
    export EI_ENABLE_WRITE_TO_FILE="no"
fi

#
# Option to enable/configure thresholding throttle
#
if [ "${ENABLE_THRESHOLD_LIMIT}" = "yes" ]; then
    export EI_ENABLE_THRESHOLD_LIMIT="yes"
else 
    export EI_ENABLE_THRESHOLD_LIMIT="no"
fi
export EI_DEFAULT_THRESHOLD=${DEFAULT_THRESHOLD}
export EI_THRESHOLD_CRITERIA=${THRESHOLD_CRITERIA}

#
# Metrics Configuration
#
export EI_IOTCORE_METRICS_DISPATCH_TIME_MS=${METRICS_SLEEPTIME_MS}

#
# S3 cache option
#
if [ "${ENABLE_CACHE_TO_S3}" = "yes" ]; then
    export EI_ENABLE_WRITE_TO_S3="yes"
else
    export EI_ENABLE_WRITE_TO_S3="no"
fi
export EI_S3_BUCKET="${S3_BUCKET}"

#
# Option for caching if enabled
#
if [ "${EI_ENABLE_WRITE_TO_FILE}" = "yes" ]; then
    if [ -d ${CACHE_FILE_DIRECTORY} ]; then
         export EI_FILE_WRITE_DIRECTORY="${CACHE_FILE_DIRECTORY}"
    else 
         echo "EI: WARNING Cache Directory ${CACHE_FILE_DIRECTORY} does not exist. Disabling Cache file writes..."
         export EI_ENABLE_WRITE_TO_FILE="no"
    fi
fi

#
# Patch Ubuntu 22+ with pipewire and systemd changes
#
if [ ! -z "${IS_UBUNTU}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Debug
echo "EI: Launch: Name: ${NAME} Device: ${DEVICE_NAME} CMD: ${CMD} ${GST_LAUNCH_ARGS}"
echo "EI: Launch: AWS SM ID/Name: ${EI_AWS_SECRET_ID}/${EI_AWS_SECRET_NAME}"
if [ ! -z "${IS_UBUNTU}" ]; then
    echo "EI: Launch(ubuntu): XDG_RUNTIME_DIR=/run/user/$UID"
    echo "EI: Launch(ubuntu): DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus"
fi
echo "EI: Include base64 image with inference: ${EI_INCLUDE_BASE64_IMAGE}"
echo "EI: Image+Inference Caching Enabled: ${EI_ENABLE_WRITE_TO_FILE}"
if [ "${EI_ENABLE_WRITE_TO_FILE}" = "yes" ]; then
   echo "EI: Image+Inference Caching Directory: ${EI_FILE_WRITE_DIRECTORY}"
fi

# Yocto/TVM support
if [ ! -z "${YOCTO}" ]; then
    export TVM_ROOT="/usr/drpaitvm"
    if [ -d ${TVM_ROOT} ]; then
        echo "YOCTO with TVM installation detected. Configuring environment..."
        export TVM_HOME="${TVM_ROOT}/tvm"
        export LD_LIBRARY_PATH="${TVM_HOME}/build_runtime:/usr/local/lib:${LD_LIBRARY_PATH}"
        export TOOLCHAIN_VERSION="3.1.21"
        export PYTHONPATH="${TVM_HOME}/python:${PYTHONPATH}"
        export SDK="/opt/poky/${TOOLCHAIN_VERSION}"
        export TRANSLATOR="${TVM_ROOT}/drp-ai"
        IS_V2L=`echo ${YOCTO} | grep v2l`
        IS_G2L=`echo ${YOCTO} | grep g2l`
        IS_V2H=`echo ${YOCTO} | grep v2h`
        if [ ! -z "${IS_V2L}" ]; then
            export PRODUCT="V2L"
        elif [ ! -z "${IS_G2L}" ]; then
            export PRODUCT="G2L"
        elif [ ! -z "${IS_V2H}" ]; then
            export PRODUCT="V2H"
        elif [ ! -z "${IS_AVNET_RZBOARD}" ]; then
            export PRODUCT="V2L"
        fi
    else
        echo "YOCTO detected but no TVM install detected - OK. Continuing..."
    fi
fi

# Local model file pull if opted
ADDITIONAL_ARGS=""
if [ ! -z "${EI_LOCAL_MODEL_FILE}" ]; then
    if [ -f "${EI_LOCAL_MODEL_FILE}" ]; then
        # DEBUG
        echo "EI: Importing from local EIM model file: ${EI_LOCAL_MODEL_FILE}..."

        # Direct runner to pull model from a local eim file
        ADDITIONAL_ARGS=" --model-file ${EI_LOCAL_MODEL_FILE} "
    else
        # Mis-configuration: EIM file not accessible
        echo "EI: WARNING: Model EIM file: ${EI_LOCAL_MODEL_FILE} not accessible. Skipping..."
    fi
fi

# DEBUG
echo "Current AWS Auth ENVIRONMENT:"
env | grep AWS

# touch the lock file...
echo "Setting LOCKFILE: ${LOCK_FILENAME}"
touch ${LOCK_FILENAME} 2>&1 1> /dev/null

# Clear
rm -f ${HOME}/edge-impulse-config.json 2>&1 1> /dev/null
rm -rf /dev/shm/edge-impulse* 2>&1 1> /dev/null

# Loop and restart as necessary...
while [ -f ${LOCK_FILENAME} ]; do
    if [ ! -z "${NAME}" ]; then
        if [ ! -z "${GST_LAUNCH_ARGS}" ]; then
            echo "EI: Launching with Name: ${NAME} | ${CMD} ${ADDITIONAL_ARGS} --gst-launch-args \"${GST_LAUNCH_ARGS}\"..."
            echo ${NAME} | ${CMD} ${ADDITIONAL_ARGS} --gst-launch-args "${GST_LAUNCH_ARGS}"
        else
            echo "EI: Launching with Name: ${NAME} | ${CMD} ${ADDITIONAL_ARGS}..."
            echo ${NAME} | ${CMD} ${ADDITIONAL_ARGS}
        fi
    else
        if [ ! -z "${GST_LAUNCH_ARGS}" ]; then
            echo "EI: Launching Raw: ${CMD} ${ADDITIONAL_ARGS} --gst-launch-args \"${GST_LAUNCH_ARGS}\"..."
            ${CMD} ${ADDITIONAL_ARGS} --gst-launch-args "${GST_LAUNCH_ARGS}"
        else
            echo "EI: Launching Raw: ${CMD} ${ADDITIONAL_ARGS}"
            ${CMD} ${ADDITIONAL_ARGS}
        fi
    fi

    # get the command invocation status at exit()... 
    STATUS=$?
    echo "EI: ${CMD} has exited with status: ${STATUS}"

    # Clear
    rm -f ${HOME}/edge-impulse-config.json 2>&1 1> /dev/null
    rm -rf /dev/shm/edge-impulse* 2>&1 1> /dev/null

    # Sleep for a bit
    sleep 5
done

echo "EI: launch.sh removing the lockfile..."
rm -f ${LOCK_FILENAME} 2>&1 1>/dev/null

echo "EI: launch.sh exiting with status ${STATUS}"
exit ${STATUS}