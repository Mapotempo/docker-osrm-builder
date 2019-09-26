#!/bin/bash

# Constants
OSM_BASE_DIR="/srv/osm"
GEOFABRIK_URL="http://download.geofabrik.de"
OSM_FR_URL="http://download.openstreetmap.fr/extracts"
TIMESTAMP="$(date +%Y%m%d)"

# Parameters
PROGRAM="$0"
REGION_FULL="$1"
REGION="$(basename ${REGION_FULL})"

# Global variables derived from parameters.
WORKSPACE="${OSM_BASE_DIR}/${REGION_FULL}"
OSM_FILE="${WORKSPACE}/${REGION}-${TIMESTAMP}.osm.pbf"
OSM_LATEST="${WORKSPACE}/${REGION}-latest.osm.pbf"
OSM_OLD="$(readlink -e ${OSM_LATEST})"

# Usage function.
usage() {
    cat <<EOF
Usage:
    ${PROGRAM} region timestamp

    region: Full region name (europe, or europe/france)
EOF

    exit 1
}

# Die function
die() {
    echo $*
    exit 1
}

# Download OSM and state files from Geofabrik.
download_geofabrik() {
    local osm_url=${GEOFABRIK_URL}/${REGION_FULL}-latest.osm.pbf

    mkdir -p ${WORKSPACE}

    # and download data.
    echo "Downloading OSM file from Geofabrik for region ${REGION}."
    wget -q ${osm_url} -O ${OSM_FILE}
    [ $? -ne 0 ] && die "Unable to download OSM file for region ${REGION}."
}

download_osm_fr() {
    local osm_url=${OSM_FR_URL}/${REGION_FULL}-latest.osm.pbf

    mkdir -p ${WORKSPACE}

    echo "Download OSM extract from OpenStreetMap France."
    wget -q ${osm_url} -O ${OSM_FILE}
    [ $? -ne 0 ] && die "Unable to download OSM file extract for region ${REGION}."
}

manage_geofabrik() {
    download_geofabrik
}

manage_osm_fr() {
    download_osm_fr
}

# Initialize or update OSM file for region.

if [ -r "${OSM_FILE}" ]; then
    echo "OSM file for region ${REGION} already exists."
    exit 0
fi

echo "Check if region ${REGION_FULL} is managed by Geofabrik."
curl -sI ${GEOFABRIK_URL}/${REGION_FULL}-updates/ | head -n 1 | grep -q '^HTTP/1.1 200 OK'
if [ $? -eq 0 ]; then
    manage_geofabrik
else
    manage_osm_fr
fi

echo "Update link for latest OSM file to ${OSM_FILE}."
ln -sf --relative ${OSM_FILE} ${OSM_LATEST}

if [ -n "${OSM_OLD}" -a ! "${OSM_OLD}" -ef "${OSM_FILE}" ]; then
    echo "Cleanup old OSM file for region ${REGION}."
    rm -f ${OSM_OLD}
fi
