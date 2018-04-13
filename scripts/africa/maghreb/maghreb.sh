#!/bin/bash

die() {
    echo $*
    exit 1
}

TARGET=$1
WORKSPACE=$(dirname ${TARGET})

OSM_DATADIR=./osm

if [ -r ${TARGET} ]; then
    echo "OSM file for region already exists."
    exit
fi

echo "Building extended OSM file."
mkdir -p ${WORKSPACE}

AREA="
    africa/algeria
    africa/tunisia
    africa/morocco
    africa/mauritania
    africa/libya
"

READPBF=
MERGE=

# Get OSM files
for extract_region_full in $AREA; do
    ./osm-manage.sh ${extract_region_full} || die "Impossible to get ${extract_region_full}."
    READPBF="$READPBF --read-pbf ${OSM_DATADIR}/${extract_region_full}/$(basename $extract_region_full)-latest.osm.pbf"
    MERGE="$MERGE --merge"
done

# Remove the last --merge
MERGE=${MERGE}_
MERGE=${MERGE/--merge_/}

# merge with osmosis
echo "Merging OSM files using osmosis."
export JAVACMD_OPTIONS="-Xms4G -Xmx8G -Djava.io.tmpdir=${WORKSPACE}"
export OSMOSIS_OPTIONS="-v"

osmosis \
    $READPBF \
    $MERGE \
    --buffer --write-pbf ${TARGET}

if [ $? -ne 0 ]; then
    rm -f ${TARGET}
    die "Unable to merge regions."
fi
