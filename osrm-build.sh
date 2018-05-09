#!/bin/bash

set -e

export PROFILE="$1"
export REGION="$2"
export NAME="$3"

shift 3

export ADDITIONAL_PARAMS="-c -f"

[ $(basename $PROFILE) == "car.lua" ] && export ADDITIONAL_PARAMS="$ADDITIONAL_PARAMS -a"

DIR=$(dirname $0)

cd ${DIR}

echo "Build data."
echo docker-compose -p builder up --no-color builder
docker-compose -p builder up --no-color builder

TARGETS=$*
LOCAL_DATA_DIR=$(readlink -f ${DIR})/osrm/data
REMOTE_DATA_DIR=/srv/osrm/data

if [ ! -r ${LOCAL_DATA_DIR}/${NAME}-latest.osrm ]; then
    echo "No data built."
    exit 1
fi

for TARGET in ${TARGETS}; do
    # 1. Get old remote link target
    REMOTE_OSRM_OLD=$(ssh ${TARGET} readlink -m ${REMOTE_DATA_DIR}/${NAME}-latest.osrm || true)

    # 2. Get new link target
    OSRM_NEW=$(readlink -m ${LOCAL_DATA_DIR}/${NAME}-latest.osrm)

    # 3. Copy files to target
    echo "Copy data to target ${TARGET}."
    rsync -a ${OSRM_NEW}* ${LOCAL_DATA_DIR}/${NAME}-latest.osrm ${TARGET}:${REMOTE_DATA_DIR}/

    # 4. Get new remote link target
    REMOTE_OSRM_NEW=$(ssh ${TARGET} readlink -m ${REMOTE_DATA_DIR}/${NAME}-latest.osrm || true)

    # 5. Load new data and cleanup old data
    if [ "${REMOTE_OSRM_OLD}" != "${REMOTE_OSRM_NEW}" ]; then
        SERVICE_NAME="osrm-$(echo ${NAME} | sed 's/_/-/g')"

        echo "Update data using datastore in service ${SERVICE_NAME}."
        ssh ${TARGET} "cd /srv/docker && docker-compose -p router exec -T ${SERVICE_NAME} osrm-datastore ${REMOTE_DATA_DIR}/$(basename ${REMOTE_OSRM_NEW})" || true

        if [ -n "${REMOTE_OSRM_OLD}" ]; then
            echo "Cleanup old data."
            ssh ${TARGET} rm -rvf ${REMOTE_OSRM_OLD}*
        fi
    else
        echo "Not loading data because it has not been updated."
    fi
done
