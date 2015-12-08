#!/bin/bash

BOLD=$'\e[0;30;1m'
SPAN_END=$'\e[m'
PROMPT="[input]"

# -------------------------------------------------------------------
# config
# -------------------------------------------------------------------

function decho()
{
    if [ ${SH_DEBUG} -eq 1 ]; then
        echo $1
    fi
}

function writeValList()
{
    cat <<EOT > editted/install_val_list
MODE=${MODE}
PG_ADMIN_USER=${PG_ADMIN_USER}
PG_ADMIN_USER_PASSWORD=${PG_ADMIN_USER_PASSWORD}
PGPORT=${PGPORT}
PGDATA=${PGDATA}
ARCHIVE_DIR=${ARCHIVE_DIR}
USE_WATCHDOG=${USE_WATCHDOG}
EOT
}

function readValList()
{
    source editted/install_val_list
}

function writeDefFile()
{
    local _PARAM=$1
    local _VAL=$2

    # Try replacing
    sed -i "s|^${_PARAM}=.*|${_PARAM}=${_VAL}|" installer.conf && return 0

    # Add
    grep ${_PARAM} installer.conf > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "${_PARAM}=${_VAL}" >> installer.conf
    fi
}


# -------------------------------------------------------------------
# check
# -------------------------------------------------------------------

function ynQuestion()
{
    local _QUESTION=$1
    local _DEFAULT=$2

    while :; do
        echo -n ${PROMPT} "${_QUESTION} [yes/no]"
        if [ "${_DEFAULT}" != "" ]; then
            echo -n " (${_DEFAULT})"
        fi
        echo ": "

        read REPLY
        if [ "${REPLY}" != "" ]; then
            case ${REPLY} in
                [yY] | [yY][eE][sS])
                    return 0
                    ;;
                [nN] | [nN][oO])
                    return 1
                    ;;
            esac

        elif [ "${_DEFAULT}" != "" ]; then
            REPLY=${_DEFAULT}
            return 0
        fi
    done
}

function clearScreen()
{
    echo -en '\e[H\e[2J'
}

function goNext()
{
    echo
    echo "Hit Enter key to continue..."
    read REPLY
    clearScreen
}

function title()
{
    echo ${BOLD}"======================================================================"${SPAN_END}
    echo $1
    echo ${BOLD}"======================================================================"${SPAN_END}
    echo
}

function subtitle()
{
    echo ${BOLD}"----------------------------------------------------------------------"${SPAN_END}
    echo $1
    echo ${BOLD}"----------------------------------------------------------------------"${SPAN_END}
    echo
}

function isInt()
{
    if [[ "$1" =~ ^[0-9]*$ ]]; then
        return 0
    else
        return 1
    fi
}

function arrayUnique()
{
    ARR=("$@")
    echo ${ARR[*]} | sed 's/\s/\n/g' | uniq
}

function isValidIPaddr()
{
    expr "$1" : "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$" #> /dev/null 2>&1
    return $?
}

# -------------------------------------------------------------------
# input
# -------------------------------------------------------------------

function userInput()
{
    local _TYPE=$1
    local _DEFAULT=$2
    local _INPUT_VAL=""
    RTN=""

    while :; do
        read _INPUT_VAL
        if [ "${_INPUT_VAL}" != "" ]; then

            # Check hostname
            if [ "${_TYPE}" == "hostname" ]; then
                if [ "${_INPUT_VAL}" == "localhost" ]; then
                    echo "NG. Please input actual hostname or IP address."
                else
                    break
                fi

            # Check integer
            elif [ "${_TYPE}" == "integer" ]; then
                isInt ${_INPUT_VAL}
                if [ $? -eq 1 ]; then
                    echo "NG. Invalid number."
                else
                    break
                fi
            fi
            break

        # Return the default value if it eixsts
        elif [ "${_DEFAULT}" != "" ]; then
            _INPUT_VAL=${_DEFAULT}
            echo "(Use default value: ${_DEFAULT})"
            break

        else
            echo "NG. You must input a value."
        fi
    done

    RTN=${_INPUT_VAL}
}

function stripQuotes()
{
    RTN=`echo "$1" | sed -e "s/'//g" -`
}

function doViaSSH()
{
    local _EXEC_USER=$1
    local _DEST=$2
    local _COMMAND=$3

    if [ "${_EXEC_USER}" == "`whoami`" ]; then
        ssh ${_DEST} "${_COMMAND}"
    else
        su - ${_EXEC_USER} -c "ssh ${_DEST} \"${_COMMAND}\""
    fi
}
