#!/bin/bash

# -------------------------------------------------------------------
# sub
# -------------------------------------------------------------------

function _installRPM()
{
    local _VAL=""

    rpm -ivh ${PACKAGE_FILE_ARR[@]}
    if [ $? -ne 0 ]; then
        echo "Failed."
        return 1
    fi

    echo
    echo "OK."
    return 0
}

# ----
# ${NOBODY_SBIN} can be changed in lib/params.sh.
# ----
function copySbin()
{
    echo "Setup the directory where copied sbin commands are put in."
    if [ ! -e ${NOBODY_SBIN} ]; then
        mkdir -p ${NOBODY_SBIN} || return 1
    fi
    chown ${APACHE_USER}:${APACHE_USER} ${NOBODY_SBIN}
    chmod 700 ${NOBODY_SBIN}

    echo "Copy original ifconfig and aprping into ${NOBODY_SBIN}."
    cp /sbin/ifconfig ${NOBODY_SBIN}
    cp /sbin/arping ${NOBODY_SBIN}
    chmod 4755 ${NOBODY_SBIN}/ifconfig
    chmod 4755 ${NOBODY_SBIN}/arping

    return 0
}

function _doPgCommand()
{
    local _NODE_NUM=$1
    local _COMMAND=$2
    doViaSSH ${PG_SUPER_USER} ${BACKEND_HOST_ARR[$_NODE_NUM]} "${PGHOME}/bin/${_COMMAND}" > /dev/null 2>&1
}

function _doQuery()
{
    local _NODE_NUM=$1
    local _QUERY=$2

    ${PGHOME}/bin/psql -h ${BACKEND_HOST_ARR[$_NODE_NUM]} -p ${BACKEND_PORT_ARR[$_NODE_NUM]} -U ${PG_SUPER_USER} template1 -c "${_QUERY}" > /dev/null 2>&1
}

function _sendToPgData()
{
    local _NODE_NUM=$1
    local _ORIG_FILE=$2
    local _RENAMED_FILE=$3

    local _DEST_HOST=${BACKEND_HOST_ARR[$_NODE_NUM]}
    local _PGDATA="${PGDATA_ARR[$_NODE_NUM]}"

    scp ${_ORIG_FILE} ${PG_SUPER_USER}@${_DEST_HOST}:${_PGDATA}/${_RENAMED_FILE}> /dev/null 2>&1
}

# ${INITDB_OPTION} can be changed in lib/params.sh.
function _doInitDB()
{
    local _NODE_NUM=$1

    local _DEST_HOST=${BACKEND_HOST_ARR[$_NODE_NUM]}
    local _DEST_DIR="${PGDATA_ARR[$_NODE_NUM]}"
    local _INITDB_STR=""

    echo "Stop PostgreSQL if exists."
    echo "chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${_DEST_DIR}"
    chown ${PG_SUPER_USER} ${PGHOME}
    _doPgCommand ${_NODE_NUM} "pg_ctl -D ${_DEST_DIR} stop -m immediate"

    echo "Set owner of the data directgory."
    doViaSSH root ${_DEST_HOST} "chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${_DEST_DIR}"

    echo "initdb ... "
    _INITDB_STR="initdb -D ${_DEST_DIR} ${INITDB_OPTION}"
    _doPgCommand ${_NODE_NUM} "${_INITDB_STR}"

    if [ $? -ne 0 ]; then
        echo "Failed. Please initdb manually like \"${PGHOME}/bin/${_INITDB_STR}\"".
        return 1
    fi
    echo "OK."
    echo

    return 0
}

function _putPostgresConfigs()
{
    local _NODE_NUM=$1

    local _DEST_HOST=${BACKEND_HOST_ARR[$_NODE_NUM]}
    local _PGDATA="${PGDATA_ARR[$_NODE_NUM]}"

    #  Put conf files (postgresql.conf is renamed when be editting).
    echo "Overwrite postgresql.conf and pg_hba.conf."
    _sendToPgData ${_NODE_NUM} editted/postgresql.conf-postgres${_NODE_NUM} postgresql.conf
    _sendToPgData ${_NODE_NUM} editted/pg_hba.conf pg_hba.conf

    # Setup online recovery.
    echo "Put scripts for online recovery ..."

    echo "- ${PGPOOL_CONF_DIR}/config_for_script"
    sed -i -e "s/\(BACKEND_NODE_NUM=\).*$/\1${_NODE_NUM}/" editted/config_for_script
    scp editted/config_for_script ${_DEST_HOST}:${PGPOOL_CONF_DIR} > /dev/null 2>&1

    echo "- ${_PGDATA}/pgpool_remote_start"
    _sendToPgData ${_NODE_NUM} templates/pgpool_remote_start pgpool_remote_start

    if [ ${REPLICATION_MODE} = "stream" ]; then
        echo "- ${_PGDATA}/basebackup-stream.sh"
        _sendToPgData ${_NODE_NUM} editted/basebackup-stream.sh basebackup-stream.sh
        echo "- ${_PGDATA}/recovery.done"
        _sendToPgData ${_NODE_NUM} editted/recovery.conf recovery.done

    else
        echo "- ${_PGDATA}/basebackup-replication.sh"
        _sendToPgData ${_NODE_NUM} editted/basebackup-replication.sh basebackup-replication.sh
        echo "- ${_PGDATA}/pgpool_recovery_pitr"
        _sendToPgData ${_NODE_NUM} editted/pgpool_recovery_pitr pgpool_recovery_pitr
    fi

    doViaSSH root ${_DEST_HOST} "]
        mkdir ${PGPOOL_LOG_DIR}
        chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${PGPOOL_LOG_DIR}
        chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${_PGDATA}/*
        chmod 755 ${_PGDATA}/*.sh
        chmod 755 ${_PGDATA}/pgpool_remote_start
        chmod 755 ${_PGDATA}/pgpool_recovery_pitr
    " > /dev/null 2>&1

    return 0
}

function _registPgFuncs()
{
    local _NODE_NUM=$1
    local _PGDATA=${PGDATA_ARR[$_NODE_NUM]}

    _doPgCommand ${_NODE_NUM} "pg_ctl -D ${_PGDATA} -w start > /dev/null 2>&1 &"
    sleep 3
    # doViaSSH root ${BACKEND_HOST_ARR[$_NODE_NUM]} "ps auwwx | grep postgres"

    echo -n "Create admin user in the database cluster..."
    _doQuery ${_NODE_NUM} "CREATE USER ${PG_ADMIN_USER} PASSWORD '${PG_ADMIN_USER_PASSWORD}' SUPERUSER"
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo "Please create the user \"${PG_ADMIN_USER}\" manually."
        echo "Continuing anyway."
        echo
    else
        echo "OK."
    fi

    echo -n "Create extension: pgpool_regclass..."
    _doQuery ${_NODE_NUM} "CREATE EXTENSION pgpool_regclass;"
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo "Please install pgpool_regclass() manually."
        echo "Continuing anyway."
        echo
    else
        echo "OK."
    fi

    echo -n "Create extension: pgpool_recovery..."
    _doQuery ${_NODE_NUM} "CREATE EXTENSION pgpool_recovery;"
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo "Please install pgpool_recovery() manually."
        echo "Continuing anyway."
        echo
    else
        echo "OK."
    fi

    _doPgCommand ${_NODE_NUM} "pg_ctl stop -D ${PGDATA}"
}

# -------------------------------------------------------------------
# main
# -------------------------------------------------------------------

function setupPgpool()
{
    local _NODE_NUM=$1
    local _MD5_PASSWD=""

    # 1. install pgpool-II and pgpoolAdmin
    ynQuestion "Do you install pgpool really?" "yes" || return 1
    echo "[1/4}] Install packages ... "
    _installRPM || return 1
    echo

    # 2. rewrite pgpool.conf
    echo -n "[2/4] Overwrite pgpool.conf..."
    cp editted/pgpool.conf-node${_NODE_NUM} ${PGPOOL_CONF_DIR}/pgpool.conf
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo "Please put pgpool.conf in the current directory to ${PGPOOL_CONF_DIR} manually."
        echo "Continuing anyway."
            echo
    else
        echo "OK."
    fi

    # 3. rewrite pcp.conf
    echo -n "[3/4] Overwrite pcp.conf..."
    if [ "${PG_ADMIN_USER_PASSWORD}" != "" ]; then
        _MD5_PASSWD=`${PGPOOL_BIN_DIR}/pg_md5 ${PG_ADMIN_USER_PASSWORD}`
        echo "${PG_ADMIN_USER}:${_MD5_PASSWD}" >> editted/pcp.conf

        cp editted/pcp.conf ${PGPOOL_CONF_DIR}
        if [ $? -ne 0 ]; then
            echo "Failed."
            echo "Please put pgpool.conf in the current directory to ${PGPOOL_CONF_DIR} manually."
            echo "Continuing anyway."
            echo
        fi
    else
        echo "OK."
    fi
    echo

    # 4. setuid for watchdog
    echo "[4/4] Setup watchdog ..."
    if [ "${USE_WATCHDOG}" == "yes" ]; then
        copySbin
        if [ $? -ne 0 ]; then
            echo "Failed."
            echo "Please put ifconfig and arping command files into ${NOBODY_SBIN} manually."
            echo "Continuing anyway."
            echo
        else
            echo "OK."
        fi
    else
        echo "Skipped because watchdog is disabled."
    fi

    echo
    return 0
}

# ----
# ${PID_FILE_DIR} can be changed in lib/params.sh.
# ${PGPOOL_LOG_DIR} can be changed in lib/params.sh.
# ----
function setupPgpoolAdmin()
{
    echo -n "[1/4] Overwrite pgmgt.conf.php..."
    cp editted/pgmgt.conf.php ${ADMIN_DIR}/conf/
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo "Please put pgmgt.conf.php in the current directory to ${ADMIN_DIR}/conf manually."
        echo "Continuing anyway."
        echo
    else
        echo "OK."
        chmod 666 ${ADMIN_DIR}/conf/pgmgt.conf.php
    fi

    echo -n "[2/4] Setup ${PID_FILE_DIR} as the directry for pgpool's pid file..."
    if [ ! -d ${PID_FILE_DIR} ]; then
        mkdir ${PID_FILE_DIR}
    fi
    chown ${APACHE_USER}:${APACHE_USER} ${PID_FILE_DIR}
    echo "OK."

    echo -n "[3/4] Setup ${PGPOOL_LOG_DIR} as pgpool's log directory..."
    if [ ! -d ${PGPOOL_LOG_DIR} ]; then
        mkdir ${PGPOOL_LOG_DIR}
    fi
    chown ${APACHE_USER}:${APACHE_USER} ${PGPOOL_LOG_DIR}
    chmod 777 ${PGPOOL_LOG_DIR}
    echo "OK."

    echo -n "[4/4] Setup ${ADMIN_DIR} as pgpoolAdmin's work directory..."
    chmod 777 ${ADMIN_DIR}/templates_c/
    echo "OK."

    echo
    return 0
}

function setupBackend()
{
    local _NODE_NUM=$1

    echo "[1/3] Install pgpool libralies."
    scp ${PGPOOL_EXTENSIONS_RPM} ${BACKEND_HOST_ARR[$_NODE_NUM]}:/tmp
    doViaSSH root ${BACKEND_HOST_ARR[$_NODE_NUM]} "
        rpm -ivh /tmp/${PGPOOL_EXTENSIONS_RPM} && rm -f /tmp/${PGPOOL_EXTENSIONS_RPM} && mkdir /etc/pgpool-II
    "
    if [ $? -ne 0 ]; then
        echo "Failed."
        echo
    fi
    echo

    # postgres #0
    if [ $? -eq 0 ]; then
        echo "[2/3] Initalize database..."
        _doInitDB ${_NODE_NUM}
        echo
        echo "[3/3] Put configuration files."
        _putPostgresConfigs ${_NODE_NUM} || return 1

    # other
    else
        echo "[2/3] Initalize database..."
        echo "Skipped".
        echo
        echo "[3/3] Put configuration files..."
        echo "Skipped".
        return 1
    fi
    echo
    return 0
}

function prepareFailOver()
{
    echo "[1/4] Put scripts for failover."
    sed -i -e 's/\(BACKEND_NODE_NUM=\).*$/\1/' editted/config_for_script
    for _NODE in ${PGPOOL_HOST_ARR[@]}; do
       scp editted/config_for_script $_NODE:${PGPOOL_CONF_DIR}
    done

    if [ ${REPLICATION_MODE} = "stream" ]; then
        for _NODE in ${PGPOOL_HOST_ARR[@]}; do
            scp templates/failover.sh $_NODE:${PGPOOL_CONF_DIR} > /dev/null 2>&1
            ssh $_NODE "chmod 755 ${PGPOOL_CONF_DIR}/failover.sh" > /dev/null 2>&1
        done
    fi

    # Set owner and permissions
    echo "[2/4] Set the owner and permission of scripts."
    for _NODE in ${PGPOOL_HOST_ARR[@]}; do
        ssh $_NODE "
        chown ${APACHE_USER}:${APACHE_USER} ${PGPOOL_CONF_DIR}/*.conf
        chown ${APACHE_USER}:${APACHE_USER} ${PGPOOL_CONF_DIR}
        chmod 444 ${PGPOOL_CONF_DIR}/config_for_script
        chmod 600 ${PGPOOL_CONF_DIR}/*.conf
        chmod 755 ${PGPOOL_CONF_DIR}
        " > /dev/null 2>&1
    done

    # Setup WAL archiving
    echo "[3/4] Created archive directory."
    mkdir -p ${ARCHIVE_DIR}
    chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${ARCHIVE_DIR}

    echo "[4/4] Regist pgpool's funtions."
    _registPgFuncs 0

    echo "OK."
    echo
    return 0
}


