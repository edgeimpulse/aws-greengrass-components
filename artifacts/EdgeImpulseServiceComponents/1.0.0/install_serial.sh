#!/bin/bash

# Defaults based on: edgeimpulse/bin/firmware/bin/linux/orin.sh
NODE_VERSION=20.12.1
LIBVIPS_VERSION=8.12.1
NPM_VERSION=10.8.1
ARCH=`uname -m`
APT=`which apt`
YUM=`which yum`
YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip)'`
OS=`uname -s | tr '[:upper:]' '[:lower:]'`
ALL=`uname -a`

#
# Is Debian, Ubuntu?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep Ubuntu`

#
# GG Component Deployment Command line params
#
INSTALL_DIR="$1"
GG_NODE_VERSION="$2"
shift 2
EI_GGC_USER_GROUPS="$*"
if [ ! -z "${GG_NODE_VERSION}" ]; then
    NODE_VERSION=${GG_NODE_VERSION}
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

# Ensure our path is set correctly... 
export PATH=${BIN_DIR}:${PATH}

announce_versions() {
    echo "GG Install Directory: ${INSTALL_DIR}"
    echo "Installing NodeJS version: ${NODE_VERSION}"
    echo "ARCH: ${ARCH}"
    echo "OS: ${OS}"
    echo "UNAME: ${ALL}"
    echo "NodeJS Machine Name: ${NODE_ARCHIVE_ARCH}"
}

install_nodejs() {
    NODE=`which node`
    if [ ! -z "${NODE}" ]; then
        NODE_VER=`node --version`
        echo "NodeJS ${NODE} already installed. Skipping install... OK. Version: ${NODE_VER}"
    else 
        echo "NodeJS not installed. Installing ${NODE_VERSION}..." 
        wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        tar -xJf node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
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

install_edge_cli() {
    EI_LINUX=`which edge-impulse-run-impulse`
    if [ ! -z "${EI_LINUX}" ]; then
        echo "EI edge-impulse-cli already installed... OK"
    else
        echo "Installing EI edge-impulse-cli..."
        npm install edge-impulse-cli -g --unsafe-perm=true
    fi
}

install_parser() {
    echo "Installing TS runner..."
    npm install -g ts-node

    echo "Installing EI/AWS serial parser..."
    PARSER_INSTALL_DIR="/home/${GREENGRASS_SERVICEUSER}/parser"
    rm -rf ${PARSER_INSTALL_DIR} 2> /dev/null
    mkdir -p ${PARSER_INSTALL_DIR} 2> /dev/null
    cp ${INSTALL_DIR}/*.ts ${INSTALL_DIR}/*.json ${INSTALL_DIR}/parser.sh ${PARSER_INSTALL_DIR}
    chmod 755 ${PARSER_INSTALL_DIR}/parser.sh
    chown -R ggc_user ${PARSER_INSTALL_DIR}
    chgrp -R ggc_user ${PARSER_INSTALL_DIR}
    chmod 644 ${PARSER_INSTALL_DIR}/package*
}

verify_install() {
    NODE=`which node`
    NODE_VER=`node --version`
    EI=`which edge-impulse-run-impulse`
    EI_VER=`edge-impulse-run-impulse --version`
    echo "Edge Impulse Serial Runner Installed!"
    echo "NodeJS: ${NODE} ${NODE_VER}"
    echo "EI: ${EI} ${EI_VER}"
}

main() {
    announce_versions $*
    install_deps $*
    install_nodejs $*
    install_npm $*
    setup_GG_service_user_perms $*
    install_edge_cli $*
    install_parser $*
    verify_install $*
}

main $*
exit 0