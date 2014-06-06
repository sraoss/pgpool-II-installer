#!/bin/bash
#
# Copyright (c) 2013-2014 PgPool Global Development Group
#
# Permission to use, copy, modify, and distribute this software and
# its documentation for any purpose and without fee is hereby
# granted, provided that the above copyright notice appear in all
# copies and that both that copyright notice and this permission
# notice appear in supporting documentation, and that the name of the
# author not be used in advertising or publicity pertaining to
# distribution of the software without specific, written prior
# permission. The author makes no representations about the
# suitability of this software for any purpose.  It is provided "as
# is" without express or implied warranty.
#
# [ About this sctipt ]
# install.sh: Install script for pgpool-II
# If you change the defalt vaklue, modify lib/params.sh.

# ===================================================================
# main
# ===================================================================

source lib/params.sh
source lib/0_common.sh
source lib/1_check.sh
source lib/2_nodes.sh
source lib/3_pgpool.sh
source lib/4_install.sh

clearScreen

# -------------------------------------------------------------------
# [1] check
# -------------------------------------------------------------------

# 1-1. check environment
checkEnv
if [ $? -ne 0 ]; then exit 1; fi
# 1-2. license agreement
agreeLiense
if [ $? -ne 0 ]; then exit 1; fi
#} 1-3. editing config?
echo
editConfigs
if [ $? -ne 0 ]; then exit 1; fi

if [ -e installer.conf ]; then
    ynQuestion "There is the file installer.conf. Do you use it?" "yes"
    if [ $? -eq 0 ]; then
        source installer.conf > /dev/null 2>&1
        mv installer.conf installer.bak
        echo "Loaded."
    else
        rm -f installer.conf
        echo "Deleted."
        touch installer.conf
    fi
fi

goNext

# -------------------------------------------------------------------
# [2] Node information
# -------------------------------------------------------------------

title "Configuring Hosts, User, SSH"

subtitle "Watchdog"
until [[ ${REPLY} =~ [yY][eE][sS] || ${REPLY} =~ [nN][oO] ]]; do
    _DEFAULT="${DEF_PGPOOL_WATCHDOG}"
    ynQuestion "Do you use the watchdog feature of pgpool?" ${_DEFAULT}
    if [ $? -eq 0 ]; then
        USE_WATCHDOG="yes"
    else
        USE_WATCHDOG="no"
    fi
    echo
done
writeDefFile "DEF_PGPOOL_WATCHDOG=${REPLY}"

subtitle "Specify the nodes in this cluster"
specifyNodes
specifyNetmask

# -------------------------------------------------------------------

goNext
title "Configuring Hosts, User, SSH"
setupSSHwoPW
if [ $? -ne 0 ]; then
    echo "Failed."
    exit 1
fi
echo
subtitle "Check PostgreSQL installed in each backends"
checkPostgresInstalled || exit 1

# Copy install scripts to pgpool#1.
if [ "${USE_WATCHDOG}" == "yes" ]; then
    scp -r ${WORK_DIR} ${PGPOOL_HOST_ARR[1]}:${REMOTE_WORK_DIR} > /dev/null 2>&1
fi

goNext

# -------------------------------------------------------------------
# [3] Editting conf files
# -------------------------------------------------------------------

# create temporary config files in editted directory
rm -rf editted/
mkdir editted/

# create editted/pgpool.conf.node{0, 1}
title "Editting conf files (pgpool#0: ${PGPOOL_HOST_ARR[0]})"
pgpoolConfNode0

if [ "${USE_WATCHDOG}" == "yes" ]; then
    title "Editting conf files (pgpool#1: ${PGPOOL_HOST_ARR[1]})"
    pgpoolConfNode1
fi

goNext

# -------------------------------------------------------------------
# [4] Install
# -------------------------------------------------------------------

title "Installation (pgpool#0: ${PGPOOL_HOST_ARR[0]})"
subtitle "Setup pgpool-II"
setupPgpool 0 || exit 1

subtitle "Setup pgpoolAdmin"
setupPgpoolAdmin || exit 1

if [ "${USE_WATCHDOG}" == "yes" ]; then
    goNext

    title "Installation (pgpool#1: ${PGPOOL_HOST_ARR[1]})"
    subtitle "Setup pgpool-II"

    doViaSSH root ${PGPOOL_HOST_ARR[1]} "
        mkdir ${REMOTE_WORK_DIR}
    " > /dev/null 2>&1
    scp -r ./* ${PGPOOL_HOST_ARR[1]}:${REMOTE_WORK_DIR}/ > /dev/null 2>&1
    echo

    doViaSSH root ${PGPOOL_HOST_ARR[1]} "
        cd ${REMOTE_WORK_DIR}
        echo \"USE_WATCHDOG=yes\" >> lib/params.sh
        source lib/params.sh
        source lib/0_common.sh
        source lib/4_install.sh
        setupPgpool 1
    " || exit 1

    subtitle "Setup pgpoolAdmin"
    doViaSSH root ${PGPOOL_HOST_ARR[1]} "
        cd ${REMOTE_WORK_DIR}
        source lib/params.sh
        source lib/0_common.sh
        source lib/4_install.sh
        setupPgpoolAdmin
    " || exit 1
fi

goNext

# -------------------------------------------------------------------
# [5] initdb and put config files
# -------------------------------------------------------------------

title "Setup backend nodes of PostgreSQL"
_VAL=""
_NODE_NUM=0
for _VAL in `arrayUnique ${BACKEND_HOST_ARR[@]}`; do
    subtitle "Setup backend node (postgres#${_NODE_NUM}: ${_VAL})"
    setupBackend ${_NODE_NUM}

    _NODE_NUM=`expr ${_NODE_NUM} + 1`
done

subtitle "Prepare the first failover"
prepareFailOver
goNext

# -------------------------------------------------------------------

title "Completed!"

service httpd start > /dev/null 2>&1
if [ "${USE_WATCHDOG}" == "yes" ]; then
    doViaSSH root ${PGPOOL_HOST_ARR[1]} "service httpd start > /dev/null 2>&1"
fi

echo "   * See pgpoolAdmin."
echo "         http://${THIS_HOST}/pgpoolAdmin/"
echo "   * Do online recovery of node 1 from pgpoolAdmin"

exit 0
