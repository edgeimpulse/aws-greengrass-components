#!/bin/bash

# Defaults based on: edgeimpulse/bin/firmware/bin/linux/orin.sh
NODE_VERSION=20.12.1
LIBVIPS_VERSION=8.12.1
NPM_VERSION=10.8.1
ARCH=`uname -m`
APT=`which apt`
YUM=`which yum`
OS=`uname -s | tr '[:upper:]' '[:lower:]'`
ALL=`uname -a`

#
# Is Debian, Ubuntu, Yocto?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep -E '(Ubuntu|RT)'`
YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip)'`
IS_AVNET_RZBOARD=`uname -a | grep -E '(rzboard)'`

#
# GG Component Deployment Command line params
#
INSTALL_DIR="$1"
GG_NODE_VERSION="$2"
GG_LIBVIPS_VERSION="$3"
INSTALL_KVSSINK="$4"
shift 4
EI_GGC_USER_GROUPS="$*"
if [ ! -z "${GG_NODE_VERSION}" ]; then
    NODE_VERSION=${GG_NODE_VERSION}
fi
if [ ! -z "${GG_LIBVIPS_VERSION}" ]; then
    LIBVIPS_VERSION=${GG_LIBVIPS_VERSION}
fi

# patch uname -a responses for quirky nodejs download filenaming conventions...
NODE_ARCHIVE_ARCH=${ARCH}
if [ "${ARCH}" = "aarch64" ]; then
    NODE_ARCHIVE_ARCH="arm64"
fi

if [ "${ARCH}" = "x86_64" ]; then
    NODE_ARCHIVE_ARCH="x64"
fi

# patch /usr/local/bin to the path...
BIN_DIR="/usr/local/bin"

# Greengrass service user
GREENGRASS_SERVICEUSER="ggc_user"
GREENGRASS_SERVICEGROUP="ggc_group"

# kvssink compile 
export SRC_DIR=/home/${GREENGRASS_SERVICEUSER}
if [ -z "${GST_PLUGIN_PATH}" ]; then
    export GST_PLUGIN_PATH="${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build"
else
    export GST_PLUGIN_PATH="${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build:${GST_PLUGIN_PATH}"
fi
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/open-source/local/lib"

# /tmp/tmp directory
TMP_TMP_DIR="/tmp/tmp"

# Ensure our path is set correctly... 
export PATH=${BIN_DIR}:${PATH}

announce_versions() {
    echo "GG Install Directory: ${INSTALL_DIR}"
    echo "ARCH: ${ARCH}"
    echo "OS: ${OS}"
    echo "UNAME: ${ALL}"
    echo "NodeJS Machine Name: ${NODE_ARCHIVE_ARCH}"
}

install_nodejs() {
    NODE=`which node`
    if [ ! -z "${NODE}" ]; then
        NODE_VER=`node --version`
        if [ "${NODE_VER}" != "v${NODE_VERSION}" ]; then
            echo "Old version of NodeJS installed. Updating to v${NODE_VERSION}..." 
            wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            tar -xJf node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            rm node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            cd node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}
            cp -R * /usr/local/
            cd ..
        else
            echo "NodeJS ${NODE} already installed. Skipping install... OK. Version: ${NODE_VER}"
        fi
    else 
        echo "NodeJS not installed. Installing ${NODE_VERSION}..." 
        wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        tar -xJf node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        rm node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        cd node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}
        cp -R * /usr/local/
        cd ..
    fi
}

install_npm() {
    NPM=`which npm`
    if [ ! -z "${NPM}" ]; then
        NPM_VER=`npm --version`
        echo "NodeJS ${NPM} already installed. Skipping install... OK. Version: ${NPM_VER}"
    else 
        echo "NodeJS npm not installed. Installing npm..." 
        if [ ! -z "${APT}" ]; then
            echo "On debian-based platform. Installing npm..."
            apt install -y npm
        elif [ ! -z "${YUM}" ]; then
            echo "On YUM-based platform. Installing npm..."
            yum -y install npm
        elif [ ! -z "${YOCTO}" ]; then
            echo "On YOCTO-based platform. Unable to install npm manually (ERROR)"
            exit 2
        else 
            echo "Platform: ${ALL} not supported. npm NOT installed"
            exit 1
        fi
    fi
}

patch_drpai_dev_permissions() {
    LIST="/dev/rgnmm /dev/rgnmmbuf /dev/uvcs /dev/vspm_if /dev/drpai0 /dev/udmabuf0"
    for i in ${LIST}; do
        if [ -r $i ]; then
            echo "Adding GG service group access to $i..."
            chgrp ${GREENGRASS_SERVICEGROUP} $i
            chmod 660 $i
        else 
            echo "DRPAI Dev Patch: $i does not appear to be readable/exist... skipping..."
        fi
    done
}

setup_GG_service_user_perms() {
    echo "Setting up GG service account group permissions"
    PERM_LIST="${EI_GGC_USER_GROUPS}"
    for PERM in ${PERM_LIST}; do
        echo "Adding group: ${PERM} for ${GREENGRASS_SERVICEUSER}..."
        usermod -aG ${PERM} ${GREENGRASS_SERVICEUSER}
    done

    # hack for ugly ubuntu 22+ pipewire gunk...
    if [ ! -z "${IS_UBUNTU}" ]; then
        echo "Adding work around for pipewire changes in ubuntu 22+..."
        loginctl enable-linger ${GREENGRASS_SERVICEUSER}
    fi
}

install_deps_debian() {
    # Default libjpeg to be used for most Ubuntu platforms...
    LIBJPEG="libjpeg-turbo8-dev"

    # hack for Debian/Raspberry Pi... ugh...
    if [ ! -z "${IS_DEBIAN}" ]; then
       echo "Adjusting libjpeg for RPi/Debian..."
        LIBJPEG="libjpeg62-turbo-dev"
    fi

    apt update
    apt install -y gcc g++ make build-essential pkg-config libglib2.0-dev libexpat1-dev sox v4l-utils ${LIBJPEG} meson ninja-build
    apt install -y gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps

    # Future: GStreamer "kvssink" plugin build support
    apt install -y cmake libssl-dev libcurl4-openssl-dev liblog4cplus-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-bad gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-tools

    # hack for ugly ubuntu 22+ pipewire gunk...
    if [ ! -z "${IS_UBUNTU}" ]; then
        echo "Adding systemd-container to work around pipewire changes in ubuntu 22+..."
        apt install -y systemd-container
    fi
}

install_deps_yum() {
    yum -y groupinstall 'Development Tools'
    yum -y install glib2-devel expat-devel libjpeg-turbo-devel
    yum -y install gstreamer1 gstreamer1-devel gstreamer1-plugins-base gstreamer1-plugins-base-tools gstreamer1-plugins-good
}

install_deps() {
    if [ ! -z "${APT}" ]; then
        echo "On debian-based platform. Installing deps..."
        install_deps_debian $*
    elif [ ! -z "${YUM}" ]; then
        echo "On YUM-based platform. Installing deps..."
        install_deps_yum $*
    elif [ ! -z "${YOCTO}" ]; then
        echo "On YOCTO-based platform. Unable to install deps. Attempting continue..."
    else 
        echo "Platform: ${ALL} not supported. No deps installed"
        exit 1
    fi
}

install_vips() {
    if [ -f /usr/local/lib/libvips.so ]; then
        echo "libvips already installed. Skipping... (OK)..."
    else
        if [ ! -z "${YOCTO}" ]; then
            echo "On YOCTO-based platform. No compile environment present. Attempting continue..."
        else 
            echo "libvips not installed. Installing..."
            wget https://github.com/libvips/libvips/releases/download/v${LIBVIPS_VERSION}/vips-${LIBVIPS_VERSION}.tar.gz
            tar xf vips-${LIBVIPS_VERSION}.tar.gz
            cd vips-${LIBVIPS_VERSION}
            ./configure
            make -j
            make install
            ldconfig
            cd ..
        fi
    fi
}

install_drpai_tvm() {
    CWD=`pwd`
    cd /usr
    if [ -r /usr/local/lib/libtvm_runtime.so ]; then
        # DRPAI TVM package already installed... continue
        echo "DRPAI TVM runtime already installed - OK. Continuing..."
    else
        # DRPAI TVM not installed. Look for the Renesas DRPAI TVM package... if found.. complete its installation. 
        if [ -r /usr/drpaitvm.tar.gz ]; then
            # DRPAI TVM Package found. Complete the installation and clean up...
            echo "Found DRPAI TVM Package... Completing Installation..."
            tar xzpf /usr/drpaitvm.tar.gz 
            cd ./drpaitvm
            chmod 755 ./ei_install.sh
            ./ei_install.sh

            # Clean up to save space...
            echo "Cleaning up DRPAI TVM Install..."
            cd /usr
            rm /usr/drpaitvm.tar.gz 2>&1 1> /dev/null
            rm ./ei_install.sh 2>&1 1> /dev/null
            echo "Completed DRPAI TVM Installation. Continuing...."
        else 
            # Platform does not have DRPAI TVM... OK. 
            echo "DRPAI_TVM not installed - OK. Continuing..."
        fi
    fi
    cd ${CWD}
}

fix_yocto_hosts_file() {
    # comment out the IPv6 entry as it monkeys with AWS SDK and GG's TES authenticator...
    sed 's/::1     localhost/#::1   localhost/g' < /etc/hosts > /etc/hosts.ei
    mv /etc/hosts /etc/hosts-$$.orig
    mv /etc/hosts.ei /etc/hosts
}

install_yocto_prereqs() {
    if [ ! -z "${YOCTO}" ]; then
        echo "Running on YOCTO based system. Installing prerequisites..."

        # DRPAI TVM Package
        install_drpai_tvm $*

        # Fix the /etc/hosts file for GG
        fix_yocto_hosts_file $*

        # update DRPAI /dev permissions
        echo "Patching DRPAI /dev permissions..."
        patch_drpai_dev_permissions $*

        # Other prereqs go here...
    else
        # Not on Yocto... OK.
        echo "Not running yocto - OK. Continuing..."
    fi
}

install_edge_impulse() {
    EI_LINUX=`which edge-impulse-linux`
    if [ ! -z "${EI_LINUX}" ]; then
        echo "EI edge-impulse-linux already installed... OK"
    else
        echo "Installing EI edge-impulse-linux..."
        npm install edge-impulse-linux -g --unsafe-perm=true
    fi
}

install_kvssink_dependencies() {
    if [ ! -z "${APT}" ]; then
        echo "Installing kvssink dependencies via apt..."
        apt install -y build-essential cmake libssl-dev libcurl4-openssl-dev liblog4cplus-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-bad gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-tools
    elif [ ! -z "${YUM}" ]; then
        echo "Installing kvssink dependencies via apt..."
        yum -y install cmake libssl-dev libcurl4-openssl-dev liblog4cplus-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-bad gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-tools
    elif [ ! -z "${YOCTO}" ]; then
        echo "On YOCTO-based platform. Unable to install kvssink dependencies manually (ERROR)"
        exit 2
    else 
        echo "Platform: ${ALL} not supported. kvssink dependencies NOT installed"
        exit 1
    fi
}

install_kvssink() {
    IS_INSTALLED=`gst-inspect-1.0 kvssink 2> /dev/null | grep -i rank`
    if [ -z "${IS_INSTALLED}" ]; then
        # install OS dependencies
        install_kvssink_dependencies $*

        # remove any previous
        rm -rf amazon-kinesis-video-streams-producer-sdk-cpp 2>&1 1>/dev/null
        rm -rf ${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp 2>&1 1>/dev/null

        # download
        git clone https://github.com/awslabs/amazon-kinesis-video-streams-producer-sdk-cpp.git
        mv amazon-kinesis-video-streams-producer-sdk-cpp ${SRC_DIR}
        cd ${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp
        mkdir build
        cd build
        cmake .. -DBUILD_GSTREAMER_PLUGIN=ON -DBUILD_JNI=TRUE

        # build!
        cd ${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp/build
        make
        make install
        chown -R ${GREENGRASS_SERVICEUSER} ${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp
        chgrp -R ${GREENGRASS_SERVICEUSER} ${SRC_DIR}/amazon-kinesis-video-streams-producer-sdk-cpp
    else
        # already installed
        echo "kvssink already installed! OK."
    fi
}

rm_tmp_tmp() {
    if [ -d ${TMP_TMP_DIR} ]; then
        echo "EI: Removing previous /tmp/tmp..."
        rm ${TMP_TMP_DIR} 2> /dev/null
    fi
}

verify_install() {
    NODE=`which node`
    NODE_VER=`node --version`
    EI=`which edge-impulse-linux`
    EI_VER=`edge-impulse-linux --version`
    echo "Edge Impulse Installed!"
    echo "NodeJS: ${NODE} ${NODE_VER}"
    echo "EI: ${EI} ${EI_VER}"

    # Optionally verify kvssink install... 
    if [ "${INSTALL_KVSSINK}" = "yes" ]; then
        IS_INSTALLED=`gst-inspect-1.0 kvssink 2> /dev/null | grep -i rank`
        if [ -z "${IS_INSTALLED}" ]; then
            echo "EI: ERROR kvssink is not installed but should be... exiting on ERROR"
            exit 10
        else
            echo "EI: kvssink is installed"
        fi
    fi
}

main() {
    announce_versions $*
    install_deps $*
    install_nodejs $*
    install_npm $*
    install_vips $*
    install_yocto_prereqs $*
    setup_GG_service_user_perms $*
    install_edge_impulse $*
    rm_tmp_tmp $*
    # Optionally install kvssink if needed for Kinesis... 
    if [ "${INSTALL_KVSSINK}" = "yes" ]; then
        install_kvssink $*
    fi
    verify_install $*
}

main $*
exit 0