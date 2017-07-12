#!/bin/bash

die() {
    echo $*
    exit 1
}

TARGET=$1
WORKSPACE=$(dirname ${target})

REGION="dom"

OSM_DATADIR=/srv/osm

if [ -r ${target} ]; then
    echo "OSM file for region DOM already exists."
    return
fi

echo "Building extended DOM OSM file."
mkdir -p ${WORKSPACE}

local extract_region_full

# Get OSM files
for extract_region_full in \
    europe/france/guadeloupe \
    europe/france/martinique \
    europe/france/guyane \
    europe/france/reunion \
    europe/france/mayotte \
    australia-oceania/new-caledonia
do
    osm-manage.sh ${extract_region_full} || die "Impossible to get ${extract_region_full}."
done

# merge with osmosis
echo "Merging OSM files using osmosis."
export JAVACMD_OPTIONS="-Xms4G -Xmx8G -Djava.io.tmpdir=${WORKSPACE}"
export OSMOSIS_OPTIONS="-v"
osmosis \
    --read-pbf ${OSM_DATADIR}/europe/france/guadeloupe/guadeloupe-latest.osm.pbf \
    --read-pbf ${OSM_DATADIR}/europe/france/martinique/martinique-latest.osm.pbf \
    --read-pbf ${OSM_DATADIR}/europe/france/guyane/guyane-latest.osm.pbf \
    --read-pbf ${OSM_DATADIR}/europe/france/reunion/reunion-latest.osm.pbf \
    --read-pbf ${OSM_DATADIR}/europe/france/mayotte/mayotte-latest.osm.pbf \
    --read-pbf ${OSM_DATADIR}/australia-oceania/new-caledonia/new-caledonia-latest.osm.pbf \
    --merge --merge --merge --merge --merge \
    --buffer --write-pbf ${target}

if [ $? -ne 0 ]; then
    rm -f ${target}
    die "Unable to merge regions."
fi
