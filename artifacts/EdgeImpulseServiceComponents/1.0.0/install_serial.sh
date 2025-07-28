#!/bin/sh

# Defaults based on: edgeimpulse/bin/firmware/bin/linux/orin.sh
NODE_VERSION="22.15.1"
LIBVIPS_VERSION="8.12.1"
NPM_VERSION="10.8.1"
ARCH=`uname -m`
APT=`which apt`
YUM=`which yum`
OS=`uname -s | tr '[:upper:]' '[:lower:]'`
ALL=`uname -a`

#
# Is Debian, Ubuntu?
#
IS_DEBIAN=`uname -v | grep Debian`
IS_UBUNTU=`uname -v | grep Ubuntu`
export YOCTO=`uname -a | grep -E '(yocto|rzboard|linux4microchip|qc|qli|frdm|5.15)'`
IS_AVNET_RZBOARD=`uname -a | grep -E '(rzboard)'`
IS_FRDM_BOARD=`uname -a | grep -E '(frdm)'`
IS_QC_BOARD=`uname -a | grep -E '(qli)'`
ROOT_DIR="/"

#
# Qualcomm special /usr handling
#
if [ ! -z "${IS_QC_BOARD}" ]; then
    ROOT_DIR="/usr"
fi

#
# Rationalize 
#
if [ ! -z "${IS_FRDM_BOARD}"]; then
    export IS_DEBIAN=""
    export IS_UBUNTU=""
    export APT=""
    export YUM=""
    export YOCTO="yocto"
fi
if [ ! -z "${IS_QC_BOARD}" ]; then
    export IS_DEBIAN=""
    export IS_UBUNTU=""
    export APT=""
    export YUM=""
    export YOCTO="yocto"
fi

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

fixup_perms() {
    cd ${TARGET_DIR}
    chown -R ${TARGET_USER}:${TARGET_GROUP} .
}

install_nodejs() {
    NODE=`which node`
    if [ ! -z "${NODE}" ]; then
        NODE_VER=`node --version`
        if [ "${NODE_VER}" != "v${NODE_VERSION}" ]; then
            echo "Other version of NodeJS installed: ${NODE_VER}. Changing to v${NODE_VERSION}..." 
            if [ -f node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz ]; then
               rm -f node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            fi
            wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            tar -xJf node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz -C /usr
            rm node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
            if [ ! -d /usr/local ]; then
                mkdir /usr/local
            fi
            if [ ! -L /usr/local/bin ]; then
                if [ ! -d /usr/local/bin ]; then
                    mkdir /usr/local/bin
                fi
            fi
            if [ ! -L /usr/local/lib ]; then
                if [ ! -d /usr/local/lib ]; then
                    mkdir /usr/local/lib
                fi
            fi
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/bin/* /usr/local/bin
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/lib/* /usr/local/lib
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}include /usr/local
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/share /usr/local
        else
            echo "NodeJS ${NODE} already installed. Skipping install... OK. Version: ${NODE_VER}"
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/bin/* /usr/local/bin
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/lib/* /usr/local/lib
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}include /usr/local
            ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/share /usr/local
        fi
    else 
        echo "NodeJS not installed. Installing ${NODE_VERSION}..." 
        if [ -f node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz ]; then
            rm -f node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        fi
        wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        tar -xJf node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz -C /usr
        rm node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}.tar.xz
        if [ ! -d /usr/local ]; then
            mkdir /usr/local
        fi
        if [ ! -L /usr/local/bin ]; then
            if [ ! -d /usr/local/bin ]; then
                mkdir /usr/local/bin
            fi
        fi
        if [ ! -L /usr/local/lib ]; then
            if [ ! -d /usr/local/lib ]; then
                mkdir /usr/local/lib
            fi
        fi
        ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/bin/* /usr/local/bin
        ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/lib/* /usr/local/lib
        ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}include /usr/local
        ln -sf /usr/node-v${NODE_VERSION}-${OS}-${NODE_ARCHIVE_ARCH}/share /usr/local
    fi

    #
    # Set the prefix to /usr/local
    #
    npm config set prefix /usr/local
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

install_deps_yocto() {
    # Set permissions on GST launch
    if [ -f /usr/bin/gst-launch-1.0 ]; then
        chmod u+s /usr/bin/gst-launch-1.0
    fi
}

install_deps() {
    if [ ! -z "${YOCTO}" ]; then
        echo "On Yocto based platform. Installing OS deps..."
        install_deps_yocto $*
    elif [ ! -z "${APT}" ]; then
        echo "On debian-based platform. Installing OS deps..."
        install_deps_debian $*
    elif [ ! -z "${YUM}" ]; then
        echo "On YUM-based platform. Installing OS deps..."
        install_deps_yum $*
    else 
        echo "install_deps(): Platform: ${ALL} not supported. No deps installed"
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

check_root_rw() {
    if [ ! -z "${YOCTO}" ]; then
        touch /usr/test
        status=$?
        if [ "${status}" != "0" ]; then
            echo "Yocto Root filesystem is RO. Changing to RW..."
            mount -o remount,rw ${ROOT_DIR}
            touch /usr/test
            status=$?
            if [ "${status}" = "0" ]; then
                echo "Root filesystem set to RW... Reboot when component install is complete"
                rm -f /tmp/usr/test
                export RESET_TO_RO="YES"
            else
                echo "Unable to enable rw the yocto root filesystem. Exiting..."
                exit 2
            fi
        else
            echo "Root filesystem already rw... OK"
            rm -f /usr/test
        fi
    else
        echo "Not on YOCTO - no need to check root rw status. OK"
    fi
}

set_root_ro() {
    if [ "${RESET_TO_RO}" = "YES" ]; then
       echo "Resetting root filesystem to RO..."
       mount -o remount,ro ${ROOT_DIR}
    fi
}

verify_install() {
    fixup_perms $*
    NODE=`which node`
    NODE_VER=`node --version`
    EI=`which edge-impulse-run-impulse`
    EI_VER=`edge-impulse-run-impulse --version`
    echo "Edge Impulse Serial Runner Installed!"
    echo "NodeJS: ${NODE} ${NODE_VER}"
    echo "EI: ${EI} ${EI_VER}"
    set_root_ro $*
}

check_service_user() {
    # User existance check
    id -u ${GREENGRASS_SERVICEUSER} 2>&1 1> /dev/null
    USER_CHECK=$?
    if [ "${USER_CHECK}" != "0" ]; then
        echo "Creating Greengrass Service User: ${GREENGRASS_SERVICEUSER} in group ${GREENGRASS_SERVICEGROUP}..."
        addgroup ${GREENGRASS_SERVICEGROUP}
        useradd ${GREENGRASS_SERVICEUSER} -d ${HOME_DIR} --shell /bin/bash --groups ${GREENGRASS_SERVICEGROUP}${GG_EXTRA_GROUPS}
        id -u ${GREENGRASS_SERVICEUSER} 2>&1 1> /dev/null
        USER_CHECK=$?
        if [ "${USER_CHECK}" != "0" ]; then
            echo "Greengrass Service User: ${GREENGRASS_SERVICEUSER} creation FAILED."
        else
            echo "Greengrass Service User: ${GREENGRASS_SERVICEUSER} creation SUCCESS."
        fi
    else
        echo "Greengrass Service User: ${GREENGRASS_SERVICEUSER} already exists... OK"
    fi

    # Home directory check
    if [ ! -d ${HOME_DIR} ]; then
        echo "Creating home directory for Greengrass Service User: ${GREENGRASS_SERVICEUSER} Home Directory: ${HOME_DIR}..."
        mkdir -p ${HOME_DIR}
        chown ${GREENGRASS_SERVICEUSER} ${HOME_DIR}
        chgrp ${GREENGRASS_SERVICEGROUP} ${HOME_DIR}
        chmod 775 ${HOME_DIR}
        echo "Greengrass Service User home directory: ${HOME_DIR} created."
    else
        echo "Greengrass Service User home directory: ${HOME_DIR} exists already (OK)."
    fi
}

main() {
    announce_versions $*
    check_root_rw $*
    check_service_user $*
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