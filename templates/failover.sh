#! /bin/sh
# Execute command by failover.
# special values:  %d = node id
#                  %h = host name
#                  %p = port number
#                  %D = database cluster path
#                  %m = new master node id
#                  %M = old master node id
#                  %H = new master node host name
#                  %P = old primary node id
#                  %% = '%' character
#                  %R = new master database cluster path
#                  %% = '%' character

# ---------------------------------------------------------------------
# prepare
# ---------------------------------------------------------------------

source /etc/pgpool-II/config_for_script

SCRIPT_LOG="$PGPOOL_LOG_DIR/failover.log"

FAILED_NODE_ID=${1}
FAILED_NODE_HOST=${2}
FAILED_NODE_PORT=${3}
FAILED_NODE_PGDATA=${4}
NEW_MASTER_NODE_ID=${5}
OLD_MASTER_NODE_ID=${6}
NEW_MASTER_NODE_HOST=${7}
OLD_PRIMARY_NODE_ID=${8}
NEW_MASTER_NODE_PORT=${9}
NEW_MASTER_NODE_PGDATA=${10}

echo "----------------------------------------------------------------------" >> ${SCRIPT_LOG}
date >> ${SCRIPT_LOG}
echo "----------------------------------------------------------------------" >> ${SCRIPT_LOG}
echo "" >> ${SCRIPT_LOG}

echo "
[ node which failed ]
FAILED_NODE_ID           ${FAILED_NODE_ID}
FAILED_NODE_HOST         ${FAILED_NODE_HOST}
FAILED_NODE_PORT         ${FAILED_NODE_PORT}
FAILED_NODE_PGDATA       ${FAILED_NODE_PGDATA}

[ before failover ]
OLD_PRIMARY_NODE_ID      ${OLD_PRIMARY_NODE_ID}
OLD_MASTER_NODE_ID       ${OLD_MASTER_NODE_ID}

[ after faiover ]
NEW_MASTER_NODE_ID       ${NEW_MASTER_NODE_ID}
NEW_MASTER_NODE_HOST     ${NEW_MASTER_NODE_HOST}
NEW_MASTER_NODE_PORT     ${NEW_MASTER_NODE_PORT}
NEW_MASTER_NODE_PGDATA   ${NEW_MASTER_NODE_PGDATA}
" >> ${SCRIPT_LOG}

# ---------------------------------------------------------------------
# Do promote only when the primary node failes
# ---------------------------------------------------------------------

if [ "${FAILED_NODE_ID}" == "${OLD_PRIMARY_NODE_ID}" ]; then
    PROMOTE_COMMAND="${PG_CTL} -D ${NEW_MASTER_NODE_PGDATA} promote"

    echo "The primary node (node ${OLD_PRIMARY_NODE_ID}) dies." >> ${SCRIPT_LOG}
    echo "Node ${NEW_MASTER_NODE_ID} takes over the primary." >> ${SCRIPT_LOG}

    echo "Execute: ${PROMOTE_COMMAND}" >> ${SCRIPT_LOG}
    ssh ${PG_SUPER_USER}@${NEW_MASTER_NODE_HOST} -T "${PROMOTE_COMMAND}" >> ${SCRIPT_LOG}

else
    echo "Node ${FAILED_NODE_ID} dies, but it's not the primary node. This script doesn't anything." >> ${SCRIPT_LOG}
fi

echo "" >> ${SCRIPT_LOG}
