#!/bin/sh

# ---------------------------------------------------------------------
# configuration
# ---------------------------------------------------------------------

CENTOS_VERSION_ARR=(6 7)
ARCHITECTURE_ARR=(x86_64)

MAJOR_VERSION=3.4
P_VERSION=3.4.1
P_RELEASE=2
P_RPM_VERSION=${P_VERSION}-${P_RELEASE}

A_VERSION=3.4.1
A_RELEASE=2
A_RPM_VERSION=${A_VERSION}-${A_RELEASE}

PG_MAJOR_VERSION_ARR=(9.3 9.4)

FILES_ARR=(
    COPYING
    README.md
    install.sh
    installer.conf.sample
    lib/
    templates/
    uninstall.sh
)

# ---------------------------------------------------------------------
# function
# ---------------------------------------------------------------------

function package()
{
    local _CENTOS_VERSION=$1
    local _ARCHITECTURE=$2
    local _PG_MAJOR_VERSION=$3

    local _PG_MAJOR_VERSION_WO_DOT=${_PG_MAJOR_VERSION/./}
    local _BASE_URL="http://www.pgpool.net/yum/rpms/${MAJOR_VERSION}/redhat/rhel-${_CENTOS_VERSION}-${_ARCHITECTURE}"
    local _PGPOOL_PG=pgpool-II-pg${_PG_MAJOR_VERSION_WO_DOT}

    local _INSTALLER_DIR="installer2-pg${_PG_MAJOR_VERSION_WO_DOT}-${P_VERSION}_rhel-${CENTOS_VERSION}-${ARCHITECTURE}"

    echo
    echo "================================================================================"
    echo "CentOS ${_CENTOS_VERSION} (${_ARCHITECTURE}) / PostgreSQL ${_PG_MAJOR_VERSION}"
    echo "================================================================================"
    echo

    mkdir ${_INSTALLER_DIR}
    cd ${_INSTALLER_DIR}

    echo
    echo "----"
    echo "put files"
    echo "----"
    echo

    for _FILE in ${FILES_ARR[@]}; do
        echo "- ${_FILE}"
        cp -rf ../../${_FILE} .
    done

    echo
    echo "----"
    echo "download RPM"
    echo "----"
    echo

    wget ${_BASE_URL}/${_PGPOOL_PG}-${P_RPM_VERSION}pgdg.rhel${_CENTOS_VERSION}.${_ARCHITECTURE}.rpm
        wget ${_BASE_URL}/${_PGPOOL_PG}-extensions-${P_RPM_VERSION}pgdg.rhel${_CENTOS_VERSION}.${_ARCHITECTURE}.rpm
    wget ${_BASE_URL}/pgpoolAdmin-${A_RPM_VERSION}pgdg.rhel${_CENTOS_VERSION}.noarch.rpm

    echo

    echo
    echo "----"
    echo "create lib/version.sh "
    echo "----"
    echo

    # scripts
    cat > lib/version.sh <<EOT
#!/bin/sh

# CentOS
CENTOS_VERSION=${_CENTOS_VERSION}

# PostgreSQL
PG_MAJOR_VERSION=${PG_MAJOR_VERSION}

# pgpool-II
MAJOR_VERSION=${MAJOR_VERSION}
P_VERSION=${P_VERSION}
P_RELEASE=${P_RELEASE}

# pgpoolAdmin
A_VERSION=${A_VERSION}
A_RELEASE=${A_RELEASE}
EOT

    cat lib/version.sh

    # ---------------------------------------------------------------------
    # tar cfz
    # ---------------------------------------------------------------------

    cd ../
    tar cfz ${_INSTALLER_DIR}.tar.gz ${_INSTALLER_DIR}

    echo
}

# ---------------------------------------------------------------------
# body
# ---------------------------------------------------------------------

rm -rf work
mkdir work
cd work

for CENTOS_VERSION in ${CENTOS_VERSION_ARR[@]}; do
    for ARCHITECTURE in ${ARCHITECTURE_ARR[@]}; do
        for PG_MAJOR_VERSION in ${PG_MAJOR_VERSION_ARR[@]}; do
            package ${CENTOS_VERSION} ${ARCHITECTURE} ${PG_MAJOR_VERSION}
        done
    done
done

ls *.tar.gz
