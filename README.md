# Ambient Loop PAT Projects

This repository contains the Ambient Loop PAT projects for running OpenStudio/EnergyPlus. The 
simulation results can be used to generate reduced order models using the [ROM Framework](https://github.com/nllong/ROM-Framework)


# Instructions

* Clone this repository

    *Note that the measures in this repository are copies from these measures [here](https://github.com/nllong/ambient-loop-measures). 
    If you need to update the measures, it is recommended to check out the measures from the other repository and edit them.
    For example, once you check out the measures, launch PAT and go to Window -> Set MyMeasure directory 
    and set the directory to the checked out measures.*
    
* If running simulations, then following instructions below on "Running Simulations" before launching PAT. If PAT is launched first, then PAT will use it's own version of OpenStudio Server which doesn't support running the algorithms needed for these projects. 

* Launch PAT (> Version 2.7.1)

* Open any of the projects

## Running Simulations

In order to run the simulations locally, you will need to run a docker-based version of OpenStudio Server. Note that you must run the commands below before launching PAT, otherwise, PAT will launch it's own version of OpenStudio Server (in local mode) on the same port as the dockerized OpenStudio Server.

* Install [Docker CE](https://docs.docker.com/install/)
* Clone [OpenStudio Server](https://github.com/nrel/openstudio-server). The develop branch should work; however, if issues arise, then checking out version 2.7.1 is recommended.

```bash
git clone https://github.com/NREL/OpenStudio-server.git

# if needed
git checkout v2.7.1
```

* Build the docker containers

```bash
cd <root-of-openstudio-server-checkout>
docker-compose build
```

* Launch the containers (include number of workers if planning on scaling)

```bash
docker-compose up
```

```bash
OS_SERVER_NUMBER_OF_WORKERS=n docker-compose up
```

* Scale the number of workers (from n above, if desired)

```bash
docker-compose scale worker=n
```

* It is helpful to remove PAT's running instance of PAT to save resources. To stop PAT from spinning up resources make sure to run the following command line a few seconds after launching and loading your PAT project.

```bash

./mongod --port 27018 --logpath

for KILLPID in `ps ax | grep -e 'ParametricAnalysisTool.app.Contents.Resources.ruby.bin.ruby' -e 'mongod.*--logpath' -e 'delayed_job' -e 'rails' | grep -v grep | awk '{print $1;}'`; do 
	echo "Killing process $KILLPID"
	kill -9 $KILLPID;
done
```

