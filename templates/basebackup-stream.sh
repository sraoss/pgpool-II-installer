#!/bin/bash
# Do base backup by rsync in streaming replication

MASTER_NODE_PGDATA=$1
DEST_NODE_HOST=$2
DEST_NODE_PGDATA=$3

# ---------------------------------------------------------------------
# prepare
# ---------------------------------------------------------------------

source /etc/pgpool-II/config_for_script

SCRIPT_LOG="${PGPOOL_LOG_DIR}/recovery.log"
DB="postgres"

# Get the node number of master
getNodeNum ${MASTER_NODE_PGDATA} || exit 1
MASTER_NODE_NUM=${RTN}
MASTER_NODE_HOST=${BACKEND_HOST_ARR[$MASTER_NODE_NUM]}
MASTER_NODE_PORT=${BACKEND_PORT_ARR[$MASTER_NODE_NUM]}
MASTER_NODE_ARCHDIR=${BACKEND_ARCHIVE_DIR_ARR[$MASTER_NODE_NUM]}

# Get the node number of destination
getNodeNum ${MASTER_NODE_PGDATA} ${DEST_NODE_HOST} || exit 1
DEST_NODE_NUM=${RTN}
DEST_NODE_HOST=${BACKEND_HOST_ARR[$DEST_NODE_NUM]}
DEST_NODE_PORT=${BACKEND_PORT_ARR[$DEST_NODE_NUM]}
DEST_NODE_ARCHDIR=${BACKEND_ARCHIVE_DIR_ARR[$DEST_NODE_NUM]}

echo "----------------------------------------------------------------------" >> ${SCRIPT_LOG}
date >> ${SCRIPT_LOG}
echo "----------------------------------------------------------------------" >> ${SCRIPT_LOG}
echo "" >> ${SCRIPT_LOG}

# ---------------------------------------------------------------------
# start base backup
# ---------------------------------------------------------------------

echo "1. pg_start_backup" >> ${SCRIPT_LOG}

${PSQL} -p ${MASTER_NODE_PORT} -U ${PG_SUPER_USER} \
    -c "SELECT pg_start_backup('Streaming Replication', true)" ${DB}

# ---------------------------------------------------------------------
# rsync db cluster
# ---------------------------------------------------------------------

echo "2. rsync: `whoami`@localhost:${MASTER_NODE_PGDATA} -> ${PG_SUPER_USER}@${DEST_NODE_HOST}:${DEST_NODE_PGDATA}" >> ${SCRIPT_LOG}

rsync -C -a -c --delete \
    --exclude postmaster.pid --exclude postmaster.opts --exclude pg_log \
    --exclude recovery.conf --exclude recovery.done --exclude pg_xlog \
    ${MASTER_NODE_PGDATA}/ \
    ${PG_SUPER_USER}@${DEST_NODE_HOST}:${DEST_NODE_PGDATA}/

ssh ${PG_SUPER_USER}@${DEST_NODE_HOST} -T "mkdir ${DEST_NODE_PGDATA}/pg_xlog"

# port
if [ "${MASTER_NODE_PORT}" != "${DEST_NODE_PORT}" ]; then
    echo "Replace port" >> ${SCRIPT_LOG}
    ssh ${PG_SUPER_USER}@${DEST_NODE_HOST} -T "
        sed -i \"s|^port[ ]*=[ ]*${MASTER_NODE_PORT}|port = ${DEST_NODE_PORT}|\" ${DEST_NODE_PGDATA}/postgresql.conf
    "
fi

# archive_command
if [ "${MASTER_NODE_ARCHDIR}" != "${DEST_NODE_ARCHDIR}" ]; then
    echo "Replace archive_command" >> ${SCRIPT_LOG}
    ssh ${PG_SUPER_USER}@${DEST_NODE_HOST} -T "
        sed -i \"s|${MASTER_NODE_ARCHDIR}|${DEST_NODE_ARCHDIR}|\" ${DEST_NODE_PGDATA}/postgresql.conf
    "
fi

# ---------------------------------------------------------------------
# recovery.conf
# ---------------------------------------------------------------------

echo "3. create recovery.conf" >> ${SCRIPT_LOG}

cat > recovery.conf <<EOF
standby_mode             = 'on'
primary_conninfo         = 'host=${MASTER_NODE_HOST} port=${MASTER_NODE_PORT} user=${PG_SUPER_USER}'
recovery_target_timeline = 'latest'
EOF
scp recovery.conf ${PG_SUPER_USER}@${DEST_NODE_HOST}:${DEST_NODE_PGDATA}/
rm -f recovery.conf

# ---------------------------------------------------------------------
# stop base backup
# ---------------------------------------------------------------------

echo "4. pg_stop_backup" >> ${SCRIPT_LOG}

${PSQL} -p ${MASTER_NODE_PORT} -U ${PG_SUPER_USER} -c "SELECT pg_stop_backup()" ${DB}

echo "" >> ${SCRIPT_LOG}
exit 0
