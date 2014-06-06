#!/bin/bash

# -------------------------------------------------------------------
# sub (pcp.conf)
# -------------------------------------------------------------------

function _doConfigPcp()
{
    local _DEFAULT=""
    subtitle "[pgpool-II] Configuration for PCP"

    cp templates/pcp.conf.sample editted/pcp.conf
    ynQuestion "Do you edit pcp.conf now?" "yes" || return 0

    if [ "${DEF_PG_ADMIN_USER}" != "" ]; then
        PG_ADMIN_USER=${DEF_PG_ADMIN_USER}
    fi
    if [ "${DEF_PG_ADMIN_USER_PASSWORD}" != "" ]; then
        PG_ADMIN_USER_PASSWORD=${DEF_PG_ADMIN_USER_PASSWORD}
    fi

    # user name
    if [ "${DEF_PG_ADMIN_USER}" != "" ]; then
        PG_ADMIN_USER=${DEF_PG_ADMIN_USER}
    fi
    echo -n "${PROMPT} username for pgpoolAdmin (defalt: ${PG_ADMIN_USER}) : "
    userInput "" ${PG_ADMIN_USER}
    PG_ADMIN_USER=${RTN}
    writeDefFile "DEF_PG_ADMIN_USER=${PG_ADMIN_USER}"

    # password
    if [ "${DEF_PG_ADMIN_USER_PASSWORD}" != "" ]; then
        PG_ADMIN_USER_PASSWORD=${DEF_PG_ADMIN_USER_PASSWORD}
    fi
    echo -n "${PROMPT} this user's password (default: ${PG_ADMIN_USER_PASSWORD}) : "
    userInput ""  ${PG_ADMIN_USER_PASSWORD}
    PG_ADMIN_USER_PASSWORD=${RTN}
    writeDefFile "DEF_PG_ADMIN_USER_PASSWORD=${PG_ADMIN_USER_PASSWORD}"

    echo
    return 0
}

# -------------------------------------------------------------------
# sub (common)
# -------------------------------------------------------------------

# get input from console and check the value if needed.
# input values is set to ${RTN}
function _checkInputParam()
{
    local _PARAM=$1
    local _DESCRIPTION=$2
    local _DEFAULT=$3

    while :; do
        echo -n ${PROMPT} ${_DESCRIPTION}
        if [ "${_DEFAULT}" != "" ]; then
            echo -n " (default: ${_DEFAULT})"
        fi
        echo -n " : "

        read _INPUT_VAL
        if [ "${_INPUT_VAL}" = "" ]; then
            if [ "${_DEFAULT}" != "" ]; then
                RTN=${_DEFAULT}
                return 0
            fi
        else
            case ${_PARAM} in
                backend_hostname*)
                    if [ ${_INPUT_VAL} = "localhost" ]; then
                        echo "NG. Please specify the host name."
                    else
                        RTN=${_INPUT_VAL}
                        return 0
                    fi
                    ;;
                *)
                    RTN=${_INPUT_VAL}
                    return 0
                    ;;
            esac
        fi
    done

    return 0
}

# rewrite param in pgpool.conf to new values
function _writePgpoolParam()
{
    local _PARAM=$1
    local _NEW_VAL=$2

    sed -i "s|^[#]*${_PARAM}[ ]*=.*$|${_PARAM} = ${_NEW_VAL}|" editted/pgpool.conf
}

# get input from console and write it to pgpool.conf
function _setPgpoolParam()
{
    local _PARAM=$1
    local _DESCRIPTION=$2
    local _DEFAULT=""

    if [ $# -eq 3 ]; then
        _DEFAULT=$3
    fi

    _checkInputParam ${_PARAM} "${_DESCRIPTION}" ${_DEFAULT}
    _NEW_VAL=${RTN}

    # Add '' to some parameters
    case ${_PARAM} in
        delegate_IP|backend_data_directory*|heartbeat_*)
            _NEW_VAL="'${_NEW_VAL}'"
            ;;
    esac

    _writePgpoolParam ${_PARAM} ${_NEW_VAL}
    writeDefFile "DEF_${_PARAM}=${_NEW_VAL}"
}

function _getPgpoolParam()
{
    local _PARAM=$1

    RTN=`grep ${_PARAM} editted/pgpool.conf | sed -e "s/${_PARAM} \+= \+\(.*\)/\1/" \
         | sed -e "s/^'\(.*\)'$/\1/"`
}

# -------------------------------------------------------------------
# sub (pg_hna.conf)
# -------------------------------------------------------------------

function _editHbaForStream()
{
    local _NETMASK_STR=""

    ed -s editted/pg_hba.conf > /dev/null 2>&1 <<EOT
/^#local *replication/s/^#//p
/^#host *replication/s/^#//p
/^#host *replication/s/^#//p
w
q
EOT

    # Allow access from backend servers each other as postgres
    for _NODE in `arrayUnique ${BACKEND_HOST_ARR[*]}`; do

        # If hostname, netmask isn't necessary.
        _NETMASK_STR=""
        if [ `isValidIPaddr ${_NODE}` -ne 0 ]; then
            _NETMASK_STR=${NETMASK}
        fi

        echo "host    replication     ${PG_SUPER_USER}     ${_NODE}    ${_NETMASK_STR}    trust" >> editted/pg_hba.conf
    done
}

function _editHbaForFailover()
{
    local _PGPOOL_HOST=$1
    local _NETMASK_STR=""

    # If hostname, netmask isn't necessary.
    _NETMASK_STR=""
    if [ `isValidIPaddr ${_PGPOOL_HOST}` -ne 0 ]; then
        _NETMASK_STR=${NETMASK}
    fi

    # Allow access from pgpool servers as both of postgres and apache
    echo "" >> editted/pg_hba.conf
    echo "# [ from ${PGPOOL_HOST} ]" >> editted/pg_hba.conf
    echo "host    all             ${PG_SUPER_USER}     ${_PGPOOL_HOST}    ${_NETMASK_STR}    trust" >> editted/pg_hba.conf
    echo "host    all             ${PG_ADMIN_USER}     ${_PGPOOL_HOST}    ${_NETMASK_STR}    trust" >> editted/pg_hba.conf
}

# -------------------------------------------------------------------
# sub (pgpool.conf)
# -------------------------------------------------------------------

function _inputPostgresDirectoryName()
{
    local _HOST=$1
    local _PARAM=$2
    local _DESCRIPTION=$3
    local _DEFAULT=$4
    local _INPUT_VAL=""
    local _HAS_NG="no"

    while :; do
        _HAS_NG="no"

        _checkInputParam "${_PARAM}" "${_DESCRIPTION}" ${_DEFAULT}
        _INPUT_VAL=${RTN}
        echo "${_INPUT_VAL}" | grep -Eq '^/'
        if [ $? -ne 0 ]; then
            echo "NG."
            echo "Hint) Specify an absolute path."
            echo
            _HAS_NG="yes"
            continue
        fi

        # If the specified directory already exists, try to remove it.
        echo -n "Check if the specified directory is empty..."
        doViaSSH root ${_HOST} "ls ${_INPUT_VAL}" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "NG."
            ynQuestion "The directory already exists. Remove?" "yes"
            if [ $? -eq 0 ]; then
                doViaSSH ${PG_SUPER_USER} ${_HOST} "rm -rf ${_INPUT_VAL}/*" > /dev/null
                if [ $? -ne 0 ]; then
                    echo "NG."
                    echo "Hint) Try to specify another directoy."
                    echo
                    _HAS_NG="yes"
                    continue
                fi
            else
                echo "NG."
                echo "Hint) Try to specify another directoy."
                echo
                _HAS_NG="yes"
                continue
            fi
        fi

        # If there is not, create the new directory.
        echo "OK."

        echo -n "Create the new directory..."
        doViaSSH root ${_HOST} "
            mkdir -p ${_INPUT_VAL} && \
            chown ${PG_SUPER_USER}:${PG_SUPER_USER} ${_INPUT_VAL}
        " > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Failed. "
            echo "Hint) Try to specify another directoy."
            echo
            _HAS_NG="yes"
        fi

        if [ "${_HAS_NG}" == "no" ]; then
            break
        fi
    done
    echo "OK."

    RTN=${_INPUT_VAL}
    return 0
}

function _setBackends()
{
    local _NODE=""
    local _NODE_NUM=0
    local _PGDATA_DEFAULT="${PGHOME}/data"
    local _ARCHIVE_DIR_DEFAULT=${ARCHIVE_DIR}

    for _NODE in ${BACKEND_HOST_ARR[@]}; do
        echo "[ PostgreSQL #${_NODE_NUM} ]"

        # Backend info (pgpool.conf)
        _writePgpoolParam "backend_hostname${_NODE_NUM}" "'${BACKEND_HOST_ARR[$_NODE_NUM]}'"
        _writePgpoolParam "backend_port${_NODE_NUM}"     "${BACKEND_PORT_ARR[$_NODE_NUM]}"
        _writePgpoolParam "backend_weight${_NODE_NUM}"    1

        # Valiidate data directory (pgpool.conf)
        echo "[1/2] Data directory"
        if [ "${DEF_PGDATA_ARR[$_NODE_NUM]}" != "" ]; then
            _PGDATA_DEFAULT=${DEF_PGDATA_ARR[$_NODE_NUM]}
        fi
        echo
        _inputPostgresDirectoryName "${_NODE}" "backend_data_directory${_NODE_NUM}" "Data directory" "${_PGDATA_DEFAULT}"
        _writePgpoolParam "backend_data_directory${_NODE_NUM}" "'${RTN}'"
        PGDATA_ARR+=("${RTN}")
        writeDefFile "DEF_PGDATA_ARR[${_NODE_NUM}]=${RTN}"
        echo

        # Validate archive directory (postgresql.conf)
        echo "[2/2] Archive directory"
        if [ "${DEF_ARCHIVE_DIR_ARR[$_NODE_NUM]}" != "" ]; then
            _ARCHIVE_DIR_DEFAULT=${DEF_ARCHIVE_DIR_ARR[$_NODE_NUM]}
        fi
        echo
        _inputPostgresDirectoryName ${_NODE} "archive_command" "the directory where to archive a logfile segment" ${_ARCHIVE_DIR_DEFAULT}
        ARCHIVE_DIR_ARR+=("${RTN}")
        writeDefFile "DEF_ARCHIVE_DIR_ARR[${_NODE_NUM}]=${RTN}"
        echo

        _NODE_NUM=`expr ${_NODE_NUM} + 1`
    done
}

function _setWatchdog()
{
    local _INPUT_VAL=""
    local _DEFAULT=${DEF_PGPOOL_WD_METHOD}

    _writePgpoolParam use_watchdog on
    _setPgpoolParam   delegate_IP  "delegate IP address" ${DEF_delegate_IP}

    # config of this watchdog
    _writePgpoolParam wd_hostname            "'${PGPOOL_HOST_ARR[0]}'"
    _writePgpoolParam wd_port                ${WATCHDOG_PORT}

    # config of another pgpool with watchdog
    _writePgpoolParam other_pgpool_hostname0 "'${PGPOOL_HOST_ARR[1]}'"
    _writePgpoolParam other_pgpool_port0     ${PGPOOL_PORT}
    _writePgpoolParam other_wd_port0         ${WATCHDOG_PORT}

    # lifecheck
    while :; do
        echo ${PROMPT} "method of watchdog lifecheck (heartbeat / query)"
        if [ "${_DEFAULT}" != "" ]; then
            echo -n "(default: ${_DEFAULT}) : "
        fi
        read _INPUT_VAL
        case ${_INPUT_VAL} in
            heartbeat|h)
                _INPUT_VAL="heartbeat"
                writeDefFile "DEF_PGPOOL_WD_METHOD=${_INPUT_VAL}"
                break
                ;;
            query|q)
                _INPUT_VAL="query"
                writeDefFile "DEF_PGPOOL_WD_METHOD=${_INPUT_VAL}"
                break
                ;;
            '')
                _INPUT_VAL=${_DEFAULT}
                if [ "${_INPUT_VAL}" == "heartbeat" ] || [ "${_INPUT_VAL}" == "query" ]; then
                    break
                fi
                ;;
        esac
    done
    _writePgpoolParam wd_lifecheck_method ${_INPUT_VAL}

    WATCHDOG_METHOD=${_INPUT_VAL}
    case $WATCHDOG_METHOD in
        heartbeat)
            _writePgpoolParam heartbeat_device0 "''"
            _writePgpoolParam heartbeat_destination0 "'${PGPOOL_HOST_ARR[0]}'"
            _writePgpoolParam heartbeat_destination_port0 "9694"
        ;;

        query)
            _writePgpoolParam wd_lifecheck_user     "'${PG_SUPER_USER}'"
            _writePgpoolParam wd_lifecheck_password "'${PG_SUPER_USER_PASSWD}'"
        ;;
    esac

    # command path (to use commands with setuid bit)
    _writePgpoolParam ifconfig_path "'${NOBODY_SBIN}'"
    _writePgpoolParam arping_path   "'${NOBODY_SBIN}'"

    # configure netmask for VIP
    _getPgpoolParam if_up_cmd
    local _VAL=`echo ${RTN} | sed -e "s/255.255.255.0/${NETMASK}/"`
    _writePgpoolParam if_up_cmd "'${_VAL}'"

    echo
}

function _doConfigPgpool()
{
    title "[pgpool-II] Configuration for pgpool"

    cp templates/pgpool.conf.sample editted/pgpool.conf
    ynQuestion "Do you edit pgpool.conf now?" "yes"
    if [ $? -ne 0 ]; then
        SKIPPED=1
        return
    fi

    # -------------------------------------------------------------------

    _writePgpoolParam listen_addresses "'*'"
    _writePgpoolParam port 9999
    _writePgpoolParam pcp_port 9898

    echo
    subtitle "Replication"
    while :; do
        echo -n ${PROMPT} "Which replication mode do you use?"
        if [ "${DEF_REPLICATION_MODE}" != "" ]; then
            echo -n " (default: ${DEF_REPLICATION_MODE})"
            echo
        fi
        echo

        echo "    native: native replication mode"
        echo "    stream: master slave mode with streaming replication"

        userInput "" ${DEF_REPLICATION_MODE}

        case ${RTN} in
        native)
            _writePgpoolParam replication_mode on
            REPLICATION_MODE="native"
            break
            ;;
        stream)
            _writePgpoolParam master_slave_mode     on
            _writePgpoolParam master_slave_sub_mode "'stream'"
            REPLICATION_MODE="stream"
            break
            ;;
        esac
    done
    writeDefFile "DEF_REPLICATION_MODE=${REPLICATION_MODE}"

    ynQuestion "Do you use load balancing?" "yes"
    if [ $? -eq 0 ]; then
        _writePgpoolParam load_balance_mode on
    fi

    ynQuestion "Do you use on memory query cache with shared memory?" "no"
    if [ $? -eq 0 ]; then
        _writePgpoolParam memory_cache_enabled on
        _writePgpoolParam memqcache_method     "'shmem'"
        _writePgpoolParam memqcache_oiddir     "'${PGPOOL_LOG_DIR}/oiddir'"
    fi

    if [ "${USE_WATCHDOG}" == "yes" ]; then
        subtitle "Watchdog"
        _setWatchdog
    fi

    goNext

    # -------------------------------------------------------------------

    title "[pgpool-II] Configuration for pgpool"

    subtitle "Backend nodes"
    _setBackends

    echo
    subtitle "Health check"
    echo "Health check will be executed by ${PG_SUPER_USER}' in 10 seconds interval."
    _writePgpoolParam health_check_user     "'${PG_SUPER_USER}'"
    _writePgpoolParam health_check_password "'${PG_SUPER_USER_PASSWD}'"
    _writePgpoolParam health_check_period   10

    echo
    subtitle "Fail over & Online recovery"
    echo "Failover and Online recovery  will be executed by ${PG_SUPER_USER}'."
    _writePgpoolParam recovery_user "'${PG_SUPER_USER}'"
    _writePgpoolParam recovery_password "'${PG_SUPER_USER_PASSWD}'"

    if [ "${REPLICATION_MODE}" = "stream" ]; then
        echo "Setup for streaming replication mode."
        echo "Streaming replication check will be executed by '${PG_SUPER_USER}'."
        _writePgpoolParam recovery_1st_stage_command "'basebackup-stream.sh'"
        _writePgpoolParam failover_command  "'${PGPOOL_CONF_DIR}/failover.sh %d %h %p %D %m %M %H %P %r %R'"
        _writePgpoolParam sr_check_user     "'${PG_SUPER_USER}'"
        _writePgpoolParam sr_check_password "'${PG_SUPER_USER_PASSWD}'"
    else
        echo "Setup for pgpool's native replication mode."
        _writePgpoolParam recovery_1st_stage_command "'basebackup-replication.sh'"
        _writePgpoolParam recovery_2nd_stage_command "'pgpool_recovery_pitr'"
    fi

    echo
    return 0
}

# -------------------------------------------------------------------
# sub (recovery.conf)
# -------------------------------------------------------------------

function _createRecoveryConfForSR()
{
    local _SCRIPT="recovery.conf"

    cp -f templates/${_SCRIPT} editted/
    ed -s editted/${_SCRIPT} <<EOT
/__REPLI_USER__/s@__REPLI_USER__@${PG_SUPER_USER}@
/__NODE0_HOST__/s@__NODE0_HOST__@${BACKEND_HOST_ARR[0]}@
/__NODE0_PORT__/s@__NODE0_PORT__@${BACKEND_PORT_ARR[0]}@
/__NODE0_ARCHDIR__/s@__NODE0_ARCHDIR__@${ARCHIVE_DIR_ARR[0]}@
w
q
EOT
}

function _createConfForScript()
{
    local _SCRIPT="config_for_script"
    local _NODE=""
    local _NODE_NUM=0

    cp -f templates/${_SCRIPT} editted/

    ed -s editted/${_SCRIPT} <<EOT
/__PGHOME__/s@__PGHOME__@${PGHOME}@
/__PG_SUPER_USER__/s@__PG_SUPER_USER__@${PG_SUPER_USER}@
/__PGPOOL_LOG_DIR__/s@__PGPOOL_LOG_DIR__@${PGPOOL_LOG_DIR}@
w
q
EOT

    for _NODE in ${BACKEND_HOST_ARR[@]}; do
        cat <<EOT >> editted/${_SCRIPT}

# [ node ${_NODE_NUM} ]
BACKEND_HOST_ARR[${_NODE_NUM}]=${BACKEND_HOST_ARR[$_NODE_NUM]}
BACKEND_PORT_ARR[${_NODE_NUM}]=${BACKEND_PORT_ARR[$_NODE_NUM]}
BACKEND_PGDATA_ARR[${_NODE_NUM}]=${PGDATA_ARR[$_NODE_NUM]}
BACKEND_ARCHIVE_DIR_ARR[${_NODE_NUM}]=${ARCHIVE_DIR_ARR[$_NODE_NUM]}
EOT
        _NODE_NUM=`expr ${_NODE_NUM} + 1`
    done
}

# -------------------------------------------------------------------
# sub (pgpoolAdmin's conf)
# -------------------------------------------------------------------

function _writeAdminParam()
{
    local _PARAM=$1
    local _NEW_VAL=$2

    sed -i "s|define('${_PARAM}',[ ]*'.*');|define('${_PARAM}', '${_NEW_VAL}');|" editted/pgmgt.conf.php
}

function _doConfigAdmin()
{
    local _DEFAULT=${DEF_PG_ADMIN_LANG}
    title "[pgpool-II] Configuration for pgpoolAdmin ..."

    cp templates/pgmgt.conf.php editted/
    ynQuestion "Do you edit pgmgt.conf.php now?" "yes" || return 0

    while :; do
        echo ${PROMPT} "Which language do you use? (en/fr/ja/zh_cn)"
        if [ "${_DEFAULT}" != "" ]; then
            echo -n "(default: ${_DEFAULT}) : "
        fi

        read _INPUT_VAL
        case ${_INPUT_VAL} in
        en | fr | ja | zh_cn )
            _writeAdminParam "_PGPOOL2_LANG" ${_INPUT_VAL}
            writeDefFile "DEF_PG_ADMIN_LANG=${_INPUT_VAL}"
            break
            ;;
        '')
            _INPUT_VAL=${_DEFAULT}
            if $(echo "${_INPUT_VAL}" | grep -Eq "en|fr|ja|zh_cn"); then
            _writeAdminParam "_PGPOOL2_LANG" ${_INPUT_VAL}
                break
            fi
            ;;
        esac
    done

    _writeAdminParam _PGPOOL2_VERSION             ${MAJOR_VERSION}
    _writeAdminParam _PGPOOL2_CONFIG_FILE         ${PGPOOL_CONF_DIR}/pgpool.conf
    _writeAdminParam _PGPOOL2_PASSWORD_FILE       ${PGPOOL_CONF_DIR}/pcp.conf
    _writeAdminParam _PGPOOL2_COMMAND             ${PGPOOL_BIN_DIR}/pgpool
    _writeAdminParam _PGPOOL2_LOG_FILE            ${PGPOOL_LOG_DIR}/pgpool.log
    _writeAdminParam _PGPOOL2_CMD_OPTION_N        1
    _writeAdminParam _PGPOOL2_PCP_DIR             ${PGPOOL_BIN_DIR}
    _writeAdminParam _PGPOOL2_STATUS_REFRESH_TIME 5

    echo
    return 0
}

# -------------------------------------------------------------------
# sub (postgresql.conf)
# -------------------------------------------------------------------

function setPostgresParam()
{
    local _PARAM=$1
    local _DESCRIPTION=$2
    local _DEFAULT=""

    if [ $# -eq 3 ]; then
        _DEFAULT=$3
    fi

    _checkInputParam ${_PARAM} "${_DESCRIPTION}" ${_DEFAULT}
    _NEW_VAL=${RTN}

    writePostgresParam ${_PARAM} ${_NEW_VAL}
}

function writePostgresParam()
{
    local _PARAM=$1
    local _NEW_VAL=$2
    local _FILENAME="editted/postgresql.conf"

    if [ $# -eq 3 ]; then
        _FILENAME=$3
    fi

    echo "${_PARAM} = ${_NEW_VAL}" >> ${_FILENAME}
}

function _doConfigPostgres()
{
    local _NODE=""
    local _NODE_NUM=0

    title "[PostgreSQL] Configuration"

    cp templates/postgresql.conf editted/postgresql.conf
    ynQuestion "Do you edit postgresql.conf now?" "yes"
    if [ $? -ne 0 ]; then
        SKIPPED=1
        return
    fi

    # [1] hot standby
    writePostgresParam listen_addresses "'*'"
    writePostgresParam archive_mode     on

    if [ ${REPLICATION_MODE} == "stream" ]; then
        writePostgresParam wal_level       hot_standby
        writePostgresParam max_wal_senders 2
        writePostgresParam hot_standby     on
    else
        writePostgresParam wal_level archive
    fi

    # [2] log
    writePostgresParam logging_collector        on
    writePostgresParam log_filename             "'%A.log'"
    writePostgresParam log_line_prefix          "'%t [%p-%l] '"
    writePostgresParam log_truncate_on_rotation on

    # -------------------------------------------------------------------
    # [3] custom vartiable
    # -------------------------------------------------------------------

    writePostgresParam pgpool.pg_ctl "'${PGHOME}/bin/pg_ctl'"

    # -------------------------------------------------------------------
    # [4] pg_hba.conf
    # -------------------------------------------------------------------

    cp templates/pg_hba.conf editted/pg_hba.conf

    # for streaming replication
    if [ ${REPLICATION_MODE} = "stream" ]; then
        _editHbaForStream
    fi

    # for failover
    for _NODE in `arrayUnique ${PGPOOL_HOST_ARR[*]}`; do
        _editHbaForFailover $_NODE
    done
}

# -------------------------------------------------------------------
# main
# -------------------------------------------------------------------

function pgpoolConfNode0()
{
    local _NODE_NUM=0
    local _NODE=""
    local _RENAMED_PG_CONF=""

    _doConfigPcp
    _doConfigPgpool
    _doConfigAdmin
    _doConfigPostgres

    echo "[1/3] Create config for failover and online recovery. "
    _createConfForScript

    echo "[2/3] Put scripts for failover"
    if [ "${REPLICATION_MODE}" == "stream" ]; then
        _createRecoveryConfForSR
        cp templates/basebackup-stream.sh editted/
        cp templates/failover.sh editted/
    else
        cp templates/basebackup-replication.sh editted/
        cp templates/pgpool_recovery_pitr editted/
    fi
    cp templates/pgpool_remote_start editted/

    # Rename postgresql.conf to the one for each backend nodes.
    echo "[3/3] Put postgresql.conf."
    for _NODE in ${PGPOOL_HOST_ARR[*]}; do
        _RENAMED_PG_CONF="postgresql.conf-postgres${_NODE_NUM}"
        cp editted/postgresql.conf editted/${_RENAMED_PG_CONF}

        writePostgresParam archive_command \
            "'cp %p ${ARCHIVE_DIR_ARR[$_NODE_NUM]}/%f </dev/null'" \
            "editted/${_RENAMED_PG_CONF}"

        writePostgresParam port ${BACKEND_PORT_ARR[$_NODE_NUM]} \
            "editted/${_RENAMED_PG_CONF}"

        _NODE_NUM=`expr ${_NODE_NUM} + 1`
    done

    cp editted/pgpool.conf editted/pgpool.conf-node0

    echo
    return 0
}

function pgpoolConfNode1()
{
    cp editted/pgpool.conf editted/pgpool.conf-node0

    echo "[1/1] Modify pgpool.conf created for pgpool#0 to use watchdog."
    _writePgpoolParam wd_hostname            "'${PGPOOL_HOST_ARR[1]}'"
    _writePgpoolParam other_pgpool_hostname0 "'${PGPOOL_HOST_ARR[0]}'"

    _getPgpoolParam wd_lifecheck_method
    if [ "${RTN}" = "heartbeat" ]; then
        _writePgpoolParam heartbeat_destination0 "'${PGPOOL_HOST_ARR[0]}'"
    fi
    cp editted/pgpool.conf editted/pgpool.conf-node1

    return 0
}
