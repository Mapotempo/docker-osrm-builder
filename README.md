Using Docker Compose to build OSRM data
=======================================

Building images
---------------

The following commands will get the source code and build the OSRM builder
and needed images:

    git clone https://github.com/mapotempo/docker-osrm-builder
    cd docker-osrm-builder
    docker-compose build

Publishing images
-----------------

To pull them from another host, we need to push the built images to
hub.docker.com:

    docker login
    docker-compose push

Running on a docker host
------------------------

First, we need to retrieve the source code and the prebuilt images:

    git clone https://github.com/mapotempo/docker-osrm-builder
    cd docker-osrm-builder
    docker-compose pull

Run the services:

    docker-compose -p builder up -d

The builder service will not stay, it is normal, the `db` and `redis-cache`
services must be running.

Initializing the builder database
---------------------------------

Before running the builder on profile `car`, we need to initialize the
database:

    TODO Alexis Lahouze 2017-06-30 

Running the builder
-------------------

In the following, you may replace the variable values by your own needs.
The PROFILE variable contains the OSRM profile file path. If the profile is in profiles
volume, you just have to set the profile file name. If you want to use a OSRM provided profile, they are located in `/usr/share/osrm/profiles`.
The REGION variable contains the name of the region. It may by a path pointing to
a region defined in Geofabrik.
The NAME variable contains the generated OSRM base name.
The ADDITIONAL_PARAMS variable contains one or more of the following arguments:
  - -c to cleanup data
  - -f to cleanup data even if it the the one currently generated
  - -a to add locations to ways in OSM file

Before running the builder we also need a profile in `docker/osrm/profiles/`.
The profile must follow the name scheme: `profile-${PROFILE}.lua`.

To run a build, enter the following command:

    PROFILE="/usr/share/osrm/profiles/foot.lua" \
    REGION="europe/france/corse" \
    NAME="foot-corse" \
    ADDITIONAL_PARAMS="-c -f" \
    docker-compose -p builder up builder

The data will be generated in `./data`.

Copy the data to another server
-------------------------------

TODO

Reload the data
---------------

Once the data has been built you need to reload it in the corresponding
container:

    docker-compose -p router exec osrm-${PROFILE}-${REGION} /usr/bin/osrm-load.sh ${PROFILE} ${REGION}
    docker-compose -p router exec osrm-${PROFILE}-${REGION} sv restart routed
    docker-compose -p router exec osrm-${PROFILE}-${REGION} sv restart isochrone

You can check if the data has been loaded in the host daemon logs:

    grep ${REGION}-${PROFILE} /var/log/daemon.log

