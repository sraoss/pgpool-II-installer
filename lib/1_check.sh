#!/bin/bash

function hasPackage()
{
    PACKAGE=$1
    PACKAGE_NAME_SHOWN=$2
    SILENT=0
    if [ $# -eq 3 ]; then
        SILENT=$3
    fi

    egrep -q $PACKAGE $WORK_DIR/rpmcheck
    if [ $? -ne 0 ]; then
        if [ $SILENT -eq 0 ]; then
            echo
            echo "Please install $PACKAGE_NAME_SHOWN."
        fi
        return 1
    fi

    return 0
}

function checkEnv()
{
    echo "check for installation ..."
    echo

    rpm -qa | grep -E "${PGPOOL_SOFTWARE_NAME}|postgresql${PG_MAJOR_VERSION_WO_DOT}|httpd|php|php-mbstring|php-pgsql" > $WORK_DIR/rpmcheck

    # OS
    if [ -f /etc/redhat-release ]; then
        if grep -q "release 6" /etc/redhat-release; then
        distribution=rhel6
        else
           echo "Your platform is not supported."
           return 1
        fi
    fi

    # pgpool-II
    hasPackage $PGPOOL_SOFTWARE_NAME $PGPOOL_SOFTWARE_NAME 1
    if [ $? -eq 0 ]; then
        echo
        echo "pgpool-II $MAJOR_VERSION is already installed."
        return 1
    fi

    # other
    hasPackage "postgresql${PG_MAJOR_VERSION_WO_DOT}-server" "PostgreSQL (postgresql${PG_MAJOR_VERSION_WO_DOT}-server)"
    if [ $? -ne 0 ]; then return 1; fi
    hasPackage "postgresql${PG_MAJOR_VERSION_WO_DOT}" "PostgreSQL (postgresql${PG_MAJOR_VERSION_WO_DOT})"
    if [ $? -ne 0 ]; then return 1; fi
    hasPackage "httpd" "Apache (httpd)"
    if [ $? -ne 0 ]; then return 1; fi
    hasPackage "php-pgsql" "PHP (php-pgsql)"
    if [ $? -ne 0 ]; then return 1; fi
    hasPackage "php-mbstring" "PHP (php-mbstring)"
    if [ $? -ne 0 ]; then return 1; fi
    hasPackage "php-[45]" "PHP"
    if [ $? -ne 0 ]; then return 1; fi

    # root
    if [ $(id -un) != root ]; then
        echo
        echo "Must be installed as root."
        return 1
    fi

    rm -f $WORK_DIR/rpmcheck
    echo "OK."
    return 0
}

function agreeLiense()
{
    echo $BOLD"================================================================="$SPAN_END
    echo
    cat COPYING
    echo
    echo $BOLD"================================================================="$SPAN_END
    ynQuestion "Do you accept the end user software license agreement?" "yes"
    return $?
}

function editConfigs()
{
    ynQuestion "Do you edit configs? If no, install will start right now without configuration." "yes"
    if [ $? -ne 0 ]; then
        doInstall
        if [ $? -eq 0 ]; then
            echo "Completed!"
            echo "All configuration should be done manually."
            exit 0
        else
            return 1
        fi
    fi
}
