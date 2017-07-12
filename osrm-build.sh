#!/bin/bash

die() {
    echo $*
    exit 1
}

usage() {
    cat >&2 <<EOF
$*

Usage:
	$0 -p profile -r region -n name [-s suffix] [-c] [-f] [-a]

Arguments:
	-p profile	Profile file path. Relative to /srv/osrm/profiles or absolute
	-r region	Full region name (europe, europe/france) or custom region name (dom)
	-n basename	Base name for output OSRM file
	-s suffix	Suffix for output OSRM file, default if a timestamp following the pattern YYYYMMDD
	-c		Cleanup old OSRM data
	-f		Force cleanup even if it removes target file
	-a		Add locations to ways before OSRM data extract

The OSRM file will be generated in the directory /srv/osrm, with the name 'basename-suffix.osrm'.
EOF

    exit 1
}

# Build OSM file for DOM-TOMs
build_osm_dom_extended(){
    local target=$1
    local workspace=$(dirname ${target})

    local region="dom"

    local OSM_DATADIR=/srv/osm

    if [ -r ${target} ]; then
        echo "OSM file for region DOM already exists."
        return
    fi

    echo "Building extended DOM OSM file."
    mkdir -p ${workspace}

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
    #export JAVACMD_OPTIONS="-Djava.io.tmpdir=${DATADIR}/france/"
    export JAVACMD_OPTIONS="-Xms4G -Xmx8G -Djava.io.tmpdir=${workspace}"
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
}

build_osm_generic(){
    local REGION_FULL=$1
    local REGION=$(basename ${REGION_FULL})

    local OSM_ORIGIN=$(readlink -e /srv/osm/${REGION_FULL}/${REGION}-latest.osm.pbf)

    if [ -r ${OSM_ORIGIN} ]; then
        echo "OSM file for region ${REGION} already exists."
        return
    fi

    osm-manage.sh ${REGION_FULL} || die "Unable to manage OSM file for region ${REGION_FULL}."
}

build_osm(){
    local REGION_FULL=$1
    local REGION=$(basename ${REGION_FULL})

    local target=$2

    local BUILD_OSM_FUNCTION="build_osm_${REGION}_extended"

    if type -t ${BUILD_OSM_FUNCTION} >/dev/null 2>&1; then
        echo "Call specific build function for region \"${REGION_FULL}\"."
        if [ "${ADD_LOCATIONS}" -eq 1 ]; then
            local intermediate=$(mktemp)

            # Build OSM data in intermediate file.
            echo "Build temporaty OSM data for region \"${REGION_FULL}\"."
            ${BUILD_OSM_FUNCTION} ${intermediate}

            # Build OSM data with locations in target file.
            echo "Build OSM data with locations for region \"${REGION_FULL}\"."
            prepare_locations ${intermediate} ${target}

            # Cleanup intermediate
            echo "Remove temporary OSM data file."
            rm -f ${intermediate}
        else
            # Build OSM data in target file.
            echo "Build OSM data for region \"${REGION_FULL}\"."
            ${BUILD_OSM_FUNCTION} ${target}
        fi
    else
        echo "Call build_osm_generic for region \"${REGION_FULL}\"."
        build_osm_generic ${REGION_FULL}

        local OSM_ORIGIN=$(readlink -e /srv/osm/${REGION_FULL}/${REGION}-latest.osm.pbf)

        if [ "${ADD_LOCATIONS}" -eq 1 ]; then
            echo "Build OSM data with locations for region \"${REGION_FULL}\"."
            prepare_locations ${OSM_ORIGIN} ${target}
        else
            echo "Link OSM data ${OSM_ORIGIN} -> ${target}."
            ln -sf --relative ${OSM_ORIGIN} ${target}
        fi
    fi

}

cleanup_link() {
    local link=$1
    local target=$(readlink -e ${link})

    echo "Cleaning target files: ${target}*"
    [[ -n "${target}" ]] && rm -vf ${target}*

    echo "Cleaning link: ${link}"
    rm -vf ${link}
}

prepare_locations() {
    local input=$1
    local output=$2

    if [ ! -r ${output} ]; then
        echo "Add locations to ways using Osmium on ${input}, writing to ${output}."
        osmium add-locations-to-ways \
            --verbose \
            --keep-untagged-nodes \
            --ignore-missing-nodes \
            -F pbf -f pbf \
            -o ${output} -O ${input} || die "Unable to add locations to ways on OSM file."
    else
        echo "OSM with locations already exists."
    fi
}

# Build OSRM data.
build_osrm(){
    local profile_path=$1
    local osm_file=$2

    local osrm_file=${osm_file%.osm.pbf}.osrm
    local osrm_latest=${osrm_file%-*}-latest.osrm

    if [ ! -r ${osrm_file} ]; then
        echo "Extracting OSRM data from OSM file ${osm_file} using profile ${profile_path}."
        /usr/bin/osrm-extract -p ${profile_path} --with-osm-metadata ${osm_file} \
            || die "Unable to extract data."
    else
        echo "Skipping OSRM data extraction because .osrm file exists."
    fi

    if [ ! -r ${osrm_file}.core ]; then
        echo "Preparing OSRM data for OSM file ${osm_file} using profile ${profile_path}."
        /usr/bin/osrm-contract ${osrm_file} || die "Unable to prepare data."
    else
        echo "Skipping OSRM data preparation because .osrm.core file exists."
    fi
}

# Global common variables
DATADIR=/srv/osrm/data

# Command line argument parsing

# Default values
SUFFIX=$(date +%Y%m%d)
ADD_LOCATIONS=0
CLEANUP_DATA=0
FORCE=0

while getopts "p:r:n:s:cfa" option
do
    case $option in
        p)
            PROFILE=${OPTARG}
            ;;
        r)
            REGION_FULL=${OPTARG}
            ;;
        n)
            BASENAME=${OPTARG}
            ;;
        s)
            SUFFIX=${OPTARG}
            ;;
        c)
            CLEANUP_DATA=1
            ;;
        f)
            FORCE=1
            ;;
        a)
            ADD_LOCATIONS=1
            ;;
        :)
            usage "Option -${OPTARG} needs a value."
            ;;
        \?)
            usage "Invalid option: -${OPTARG}."
            ;;
        *)
            usage
            ;;
      esac
done

shift $((OPTIND-1))

# Profile path resolution
if [[ "${PROFILE}" == /* ]]; then
    PROFILE_PATH=${PROFILE}
else
    PROFILE_PATH="/srv/osrm/profiles/${PROFILE}"
fi

# Mandatory argument presence checking
[ -z "${PROFILE}" ] && usage "Profile must be provided."
[ -z "${REGION_FULL}" ] && usage "Region must be provided."
[ -z "${BASENAME}" ] && usage "Base name must be provided."

# Profile file existence checking
[[ ! -r ${PROFILE_PATH} ]] && die "Profile file '${PROFILE_PATH}' does not exist or is not readable."

# Build

# Initialize global variables needed by the build.
REGION=$(basename ${REGION_FULL})

OSM_FILE=${DATADIR}/${BASENAME}-${SUFFIX}.osm.pbf
OSM_LATEST=${DATADIR}/${BASENAME}-latest.osm.pbf

OSRM_FILE=${DATADIR}/${BASENAME}-${SUFFIX}.osrm
OSRM_LATEST=${DATADIR}/${BASENAME}-latest.osrm

# Handle cleanup
if [ "${CLEANUP_DATA}" -eq 1 ]; then
    if [ ! "${OSRM_LATEST}" -ef "${OSRM_FILE}" -o ${FORCE} -eq 1 ]; then
        cleanup_link ${OSRM_LATEST}
    else
        echo "Not cleaning up ${OSRM_LATEST} because it references the building file. Use -f instead."
    fi

    if [ ! "${OSM_LATEST}" -ef "${OSM_FILE}" -o ${FORCE} -eq 1 ]; then
        cleanup_link ${OSM_LATEST}
    else
        echo "Not cleaning up ${OSM_LATEST} because it references the building file. Use -f instead."
    fi
fi

# Fetch latest OSM data.
build_osm ${REGION_FULL} ${OSM_FILE}

echo "Linking latest OSM to ${OSM_FILE}."
ln -sf --relative ${OSM_FILE} ${OSM_LATEST}

# Build OSRM files
build_osrm ${PROFILE_PATH} ${OSM_FILE}

# Create a link to the latest OSRM for the next start
echo "Linking latest OSRM to ${OSRM_FILE}."
ln -sf --relative ${OSRM_FILE} ${OSRM_LATEST}
