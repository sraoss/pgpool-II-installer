#!/bin/bash

# -------------------------------------------------------------------
# sub (input values)
# -------------------------------------------------------------------

function _inputHostName()
{
    local _CONF_NODE=$1
    local _INPUT_NODE=""
    local _DEFAULT=${_CONF_NODE}

    echo -n ${PROMPT} "Specify hostname or IP address "
    if [ "${_DEFAULT}" != "" ]; then
        echo -n " (default: ${_DEFAULT}) "
    fi
    echo ": "
    userInput hostname ${_DEFAULT}

    return 0
}

function _inputPort()
{
    local _DEFAULT=$1
    local _CONF_NODE=$2
    local _INPUT_NODE=""

    if [ "${_CONF_NODE}" != "" ]; then
       _DEFAULT=${_CONF_NODE}
    fi

    echo ${PROMPT} "Specify port number (default: ${_DEFAULT}) : "
    userInput integer ${_DEFAULT}

    return 0
}

# -------------------------------------------------------------------
# sub (Apache user)
# -------------------------------------------------------------------

function setupUserApache()
{
    local _APACHE_HOME="/home/${APACHE_USER}"

    id ${APACHE_USER} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Create apache user."
        useradd -d ${_APACHE_HOME} -s /bin/bash ${APACHE_USER} || return 1

    else
        echo "Create ${_APACHE_HOME} as ${APACHE_USER}'s home directory."
        if [ ! -e ${_APACHE_HOME} ]; then
            mkdir ${_APACHE_HOME} -m 700
        fi
        chown ${APACHE_USER}:${APACHE_USER} ${_APACHE_HOME}

        # Check to login to apache
        su - ${APACHE_USER} -c "exit"
        if [ $? -ne 0 ]; then
            # Stop httpd.
            # Because if there are processes of apache user, usermod fails.
            echo "Httpd must be stopped. Stop httpd"
            service httpd stop
            if [ `ps -ef | grep ${APACHE_USER} | wc -l` -eq 0 ]; then
                return 1
            fi

            echo "Modify apache user's info."
            usermod -d ${_APACHE_HOME} -s /bin/bash ${APACHE_USER} || return 1
        fi
    fi

    echo "Try to execute 'su - apache'."
    su - ${APACHE_USER} -c "exit" || return 1

    echo
    return 0
}

# -------------------------------------------------------------------
# sub (SSH)
# -------------------------------------------------------------------

function _createSSHkey()
{
    local _THIS_USER=$1

    local _HOME=`eval echo ~${_THIS_USER}`
    local _SSH_DIR=${_HOME}/.ssh

    rm ${_SSH_DIR}/id_rsa* > /dev/null 2>&1
    su - ${_THIS_USER} -c "ssh-keygen -q -t rsa -P '' -f ${_SSH_DIR}/id_rsa << EOF

EOF"
    return $?
}

function _createSSHConfig()
{
    local _THIS_USER=$1

    local _HOME=`eval echo ~${_THIS_USER}`
    local _SSH_DIR=${_HOME}/.ssh
    local _SSH_CONFIG=${_SSH_DIR}/config

    if [ ! -e ${_SSH_CONFIG} ]; then
        touch ${_SSH_CONFIG}
    fi

    for _NODE in `arrayUnique ${PGPOOL_HOST_ARR[*]} ${BACKEND_HOST_ARR[*]}`; do
        if $(grep -Eq "^Host ${_NODE}$" "${_SSH_CONFIG}"); then
            break
        fi
        cat >>${_SSH_CONFIG} <<EOT

# Added by pgpool-II install.sh
Host ${_NODE}
StrictHostKeyChecking no
EOT
    done
}

function _putSSHkey()
{
    local _THIS_USER=$1
    local _REMOTE_USER=$2
    local _REMOTE_HOST=$3

    local _HOME=`eval echo ~${_THIS_USER}`
    local _SSH_DIR=${_HOME}/.ssh
    local _HOSTNAME=`hostname`

    echo "[ssh] ${_THIS_USER}@${_HOSTNAME}-> ${_REMOTE_USER}@${_REMOTE_HOST}"

    if [ ! -e ${_SSH_DIR}/id_rsa ] || [ ! -e ${_SSH_DIR}/id_rsa.pub ]; then
        echo "Create the new SSH key."
        _createSSHkey ${_THIS_USER} || return 1
        _createSSHConfig ${_THIS_USER} || return 1
    else
        echo "The SSH key for ${THIS_USER}@${_HOSTNAME} was found. Use ${_SSH_DIR}/id_rsa."
    fi

    echo "Copy the public key to ${_REMOTE_USER}@${_REMOTE_HOST}."
    ssh-copy-id -i ${_SSH_DIR}/id_rsa.pub ${_REMOTE_USER}@${_REMOTE_HOST} > /dev/null 2>&1 || return 1

    echo -n "Try SSH..."
    su - ${_THIS_USER} -c \
        "ssh -o StrictHostKeyChecking=no ${_REMOTE_USER}@${_REMOTE_HOST} exit" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Failed."
        return 1
    fi
    echo "OK."

    echo
    return 0
}

# Log hostnames to installer.conf which is userd at the next time to install
# and hostname.conf which is used to setup SSH in pgpool#1.
function _logConfNodes()
{
    local _NODE_NUM=0
    local _NODE=""

    rm -f hostname.conf > /dev/null 2>&1

    # pgpool
    for _NODE in ${PGPOOL_HOST_ARR[@]}; do
        writeDefFile "DEF_PGPOOL_HOST_ARR[${_NODE_NUM}]=${_NODE}"
        _NODE_NUM=`expr ${_NODE_NUM} + 1`
    done

    # PostgreSQL
    _NODE_NUM=0
    for _NODE in ${BACKEND_HOST_ARR[@]}; do
        writeDefFile "DEF_BACKEND_HOST_ARR[${_NODE_NUM}]=${_NODE}"
        writeDefFile "DEF_BACKEND_PORT_ARR[${_NODE_NUM}]=${BACKEND_PORT_ARR[$_NODE_NUM]}"
        _NODE_NUM=`expr ${_NODE_NUM} + 1`
    done
}

function copyScripts()
{
    local _DEST_HOST=$1

    doViaSSH root ${_DEST_HOST} "
        mkdir ${REMOTE_WORK_DIR}
    " > /dev/null 2>&1
    scp -r ./lib/ root@${_DEST_HOST}:${REMOTE_WORK_DIR}
}

function copySshKeyToUser()
{
    local _USER=$1
    local _HOME=`eval echo ~${_USER}`

    cp -R /root/.ssh/ ${_HOME} || return 1
    chown -R ${_USER}:${_USER} ${_HOME}/.ssh/ || return 1
}

function _setupSshAnotherPgpoolServer()
{
    local _POSTGRES_HOME=`eval echo ~${PG_SUPER_USER}`
    local _APACHE_HOME=`eval echo ~${APACHE_USER}`
    local _DEST_HOST=${PGPOOL_HOST_ARR[1]}

    echo "[1/2] Setup apache's home directory."

    # Prepare scripts
    copyScripts ${_DEST_HOST} > /dev/null 2>&1 || return 1

    # Copy the private key and the config
    scp ~/.ssh/{id_rsa,config} ${_DEST_HOST}:~/.ssh/ > /dev/null 2>&1

    # Make apache user to be able to login and create /home/apache
    doViaSSH root ${_DEST_HOST} "
        cd ${REMOTE_WORK_DIR}
        source lib/params.sh
        source lib/2_nodes.sh
        setupUserApache
    " > /dev/null 2>&1 || return 1

    echo "[2/2] Copy the same private keys as root@${PGPOOL_HOST_ARR[0]}."

    # Put a private key in each uesers
    doViaSSH root ${_DEST_HOST} "
        cd ${REMOTE_WORK_DIR}
        source lib/params.sh
        source lib/2_nodes.sh
        copySshKeyToUser ${PG_SUPER_USER}
        copySshKeyToUser ${APACHE_USER}
    " > /dev/null 2>&1 || return 1
}

# -------------------------------------------------------------------
# main
# -------------------------------------------------------------------

# $PGPOOL_x_HOST, $PGPOOL_x_PORT, $DB_x_HOST, $DB_x_PORT
function specifyNodes()
{
    echo "* Hosts where pgpool runs"

    for _NODE_NUM in `seq 0 1`; do
        echo "[ pgpool #${_NODE_NUM} ]"
        _inputHostName ${DEF_PGPOOL_HOST_ARR[$_NODE_NUM]} && PGPOOL_HOST_ARR+=( ${RTN} )
        echo

        if [ "${USE_WATCHDOG}" == "no" ]; then
            break
        fi
    done

    echo
    echo "* Hosts where PostgreSQL runs"
    echo

    # ----
    # TODO:
    # Prohibit to specify BACKEND_COUNT, because failover scripts expects
    # only the condition of 2 backend nodes,
    # ----
    #
    # echo "How many backends of PostgreSQL do you use? (default: 2)"
    # userInput integer 2
    # BACKEND_COUNT=`expr ${RTN} - 1`
    BACKEND_COUNT=1

    for _NODE_NUM in `seq 0 ${BACKEND_COUNT}`; do
        echo "[ PostgreSQL #${_NODE_NUM} ]"
        _inputHostName ${DEF_BACKEND_HOST_ARR[$_NODE_NUM]} && BACKEND_HOST_ARR+=( ${RTN} )
        _inputPort ${PGPORT} ${DEF_BACKEND_PORT_ARR[$_NODE_NUM]} && BACKEND_PORT_ARR+=( ${RTN} )
        echo
    done

    _logConfNodes

    return 0
}

# $NETMASK
function specifyNetmask()
{
    echo "[ netmask ]"
    echo -n ${PROMPT} "Specify netmask (default: ${NETMASK}) : "
    userInput netmask ${NETMASK} && NETMASK=${RTN}
    writeDefFile "NETMASK=${NETMASK}"
}

# Setup SSH
# (If there isn't the user "postgres", install.sh failes)
function setupSSHwoPW()
{
    local _THIS_USER=`whoami`
    local _HOME=`eval echo ~${_THIS_USER}`
    local _SSH_DIR=${_HOME}/.ssh
    local _NODE=""

    # Make apache user to be able to login and create /home/apache
    setupUserApache || return 1

    # ---------------------------------------------------------------------
    # Setup in pgpool#1
    # ---------------------------------------------------------------------

    subtitle "Setup password-less access over SSH [ pgpool#0 ]"

    # For convenience to install pgpool
    echo "* Setup SSH from ${PGPOOL_HOST_ARR[0]} ..."
    echo
    for _NODE in `arrayUnique ${PGPOOL_HOST_ARR[*]}`; do
        _putSSHkey root root ${_NODE} || return 1
    done

    # Copy root's ssh directory to postgres and apache user.
    copySshKeyToUser ${PG_SUPER_USER} > /dev/null 2>&1 || return 1
    copySshKeyToUser ${APACHE_USER} > /dev/null 2>&1 || return 1

    # ---------------------------------------------------------------------
    # Setup in pgpool#2
    # ---------------------------------------------------------------------

    if [ "${USE_WATCHDOG}" == "yes" ]; then
        subtitle "Setup password-less access over SSH [ pgpool#1 ]"

        echo "* Setup SSH from ${PGPOOL_HOST_ARR[1]} ..."
        echo
        _setupSshAnotherPgpoolServer || return 1
    fi
    echo

    # ---------------------------------------------------------------------
    # Setup in backends
    # ---------------------------------------------------------------------

    # Copy /root/.ssh in pgpool#1's to each backends.
    _NODE_NUM=0
    for _NODE in `arrayUnique ${BACKEND_HOST_ARR[*]}`; do
        subtitle "Setup password-less access over SSH [ PostgreSQL#${_NODE_NUM} ]"

        echo "* Setup SSH from ${_NODE} ..."
        echo
        echo "[1/1] Copied the same private keys as root@${PGPOOL_HOST_ARR[0]}."

        _putSSHkey root root ${_NODE} || return 1

        # Prepare scripts
        copyScripts ${_NODE} > /dev/null 2>&1 || return 1

        # Copy the private key and config
        scp ~/.ssh/{id_rsa,config} ${_NODE}:~/.ssh/ > /dev/null 2>&1

        # Copy root's private key as postgres's apache's.
        doViaSSH root ${_NODE} "
            cd ${REMOTE_WORK_DIR}
            source lib/params.sh
            source lib/2_nodes.sh
            copySshKeyToUser ${PG_SUPER_USER}
        "
        _NODE_NUM=`expr ${_NODE_NUM} + 1`
        echo
    done

    return 0
}

# Is there PostgreSQL in backend nodes?
function checkPostgresInstalled()
{
    local _DEFAULT=${PGHOME}
    local _NODE=""
    local _RESULT=0
    local _HAS_NG="no"

    # ====
    # RESTRICTION: PostgreSQL in backends must be installed by RPM, too.
    # ====
    PGHOME=${_DEFAULT}
    for _NODE in `arrayUnique ${BACKEND_HOST_ARR[*]}`; do
        echo "Confirm if there is PostgreSQL in ${_NODE}."

        doViaSSH ${PG_SUPER_USER} ${PG_SUPER_USER}@${_NODE} "
            test -s ${PGHOME}/bin/pg_config
        " > /dev/null 2>&1

        if [ $? -ne 0 ]; then
            echo "Not found ${PGHOME}/bin/pg_config in ${_NODE}."
            return 1
        fi
    done
    return 0

    # ====
    # TODO: Must change the way to create and copy config_for_script to use this.
    # ====
    if [ "${DEF_PGHOME}" != "" ]; then
        _DEFAULT=${DEF_PGHOME}
    fi

    while :; do
        # Input the PostgreSQL bin direcgtory
        echo ${PROMPT} "the directory where PostgreSQL is installed (default: ${_DEFAULT}): "
        userInput "" ${_DEFAULT} && PGHOME=${RTN}

        # Check if there is pg_config in each backends
        _HAS_NG="no"
        for _NODE in `arrayUnique ${BACKEND_HOST_ARR[*]}`; do
            echo "Confirm if there is PostgreSQL in ${_NODE}."

            doViaSSH ${PG_SUPER_USER} ${PG_SUPER_USER}@${_NODE} "
                test -s ${PGHOME}/bin/pg_config
            " > /dev/null 2>&1

            if [ $? -ne 0 ]; then
                echo "Not found ${PGHOME}/bin/pg_config in ${_NODE}."
                _HAS_NG="yes"
            fi
        done

        # If all backends have PostgreSQL, this check finishes.
        if [ ${_HAS_NG} == "no" ]; then
            break
        fi
    done

    # Log the value in installer.conf
    writeDefFile "DEF_PGHOME=${PGHOME}"

    return 0
}
