#!/bin/bash

# ---------------------------------------------------------------------
# common
# ---------------------------------------------------------------------

PATH="/bin:/sbin:/usr/bin:/usr/sbin"
SH_DEBUG=0
WORK_DIR=`pwd`
REMOTE_WORK_DIR="/tmp/pgpool-installer"
ARCHITECTURE=`uname -i`

# ---------------------------------------------------------------------
# node info
# ---------------------------------------------------------------------

# params to be modified in install.sh
PGPOOL_HOST_ARR=()
PGPOOL_PORT_ARR=()
BACKEND_HOST_ARR=()
BACKEND_PORT_ARR=()
PGDATA_ARR=()
ARCHIVE_DIR_ARR=()
NETMASK="255.255.255.0"

# ---------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------

# params for packagers
PG_MAJOR_VERSION=9.3
PG_MAJOR_VERSION_WO_DOT=${PG_MAJOR_VERSION/./}
POSTGRES_PACKAGE_NAME="postgresql${PG_MAJOR_VERSION_WO_DOT}"

# params to specify in only this file
PG_SUPER_USER="postgres"
PG_SUPER_USER_PASSWD=${PG_SUPER_USER}
PG_SUPER_USER_HOME=`eval echo ~${PG_SUPER_USER}`
INITDB_OPTION="--no-locale -E UTF8"

# params to be modified in install.sh
PGPORT=5432
PGHOME="/usr/pgsql-${PG_MAJOR_VERSION}"
PGDATA="${PG_SUPER_USER_HOME}/data"
ARCHIVE_DIR="${PG_SUPER_USER_HOME}/archivedir"

# ---------------------------------------------------------------------
# pgpool-II
# ---------------------------------------------------------------------

# params for packagers (users shouldn't change)
MAJOR_VERSION=3.3
DIST="pgdg"
PGPOOL_SOFTWARE_NAME="pgpool-II"
P_VERSION=3.3.3
P_RELEASE=1
PGPOOL_RPM="${PGPOOL_SOFTWARE_NAME}-pg${PG_MAJOR_VERSION_WO_DOT}-${P_VERSION}-${P_RELEASE}.${DIST}.${ARCHITECTURE}.rpm"

# params to not be changed (specified in RPM spec file)
PGPOOL_BIN_DIR="/usr/bin"
PGPOOL_CONF_DIR="/etc/pgpool-II"

# params to specify in only this file
PGPOOL_PORT=9999
PCP_PORT=9898
WATCHDOG_PORT=9000
NOBODY_SBIN="/var/private/nobody/sbin"
PID_FILE_DIR="/var/run/pgpool/"
PGPOOL_LOG_DIR="/var/log/pgpool"

# params to be modified in install.sh
MODE="stream"
USE_WATCHDOG="no"

# ---------------------------------------------------------------------
# pgpoolAdmin
# ---------------------------------------------------------------------

# params for packagers (users shouldn't change)
ADMIN_SOFTWARE_NAME="pgpoolAdmin"
A_VERSION=3.3.1
A_RELEASE=1
PGPOOL_ADMIN_RPM="${ADMIN_SOFTWARE_NAME}-${A_VERSION}-${A_RELEASE}.${DIST}.noarch.rpm"

# params to not be changed (specified in RPM spec file)
ADMIN_DIR="/var/www/html/pgpoolAdmin"

# params to be modified in install.sh
APACHE_USER="apache"
PG_ADMIN_USER="admin"
PG_ADMIN_USER_PASSWORD="pgpool"

# ---------------------------------------------------------------------
# software
# ---------------------------------------------------------------------

PACKAGE_FILE_ARR=(
    ${PGPOOL_RPM}
    ${PGPOOL_ADMIN_RPM}
)
