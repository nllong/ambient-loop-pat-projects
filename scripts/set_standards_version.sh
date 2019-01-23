#!/bin/bash -e

# This script will enable a user to change a single gem in the list of accessible gems. The script will create the NEW_GEMFILE_DIR if it
# does not already exist.

if [[ (-z $1) || (-z $2) || (-z $3) || (-z $4) ]] ; then
    echo "Expecting script to have 4 parameters:"
    echo "  1: Path to where OpenStudio is installed on the system. Docker: /usr/local/openstudio-2.7.1. OSX: /Applications/openstudio-2.7.0/Ruby" 
    echo "  2: Name of the exiting gem to replace, e.g. openstudio-standards"
    echo "  3: Argument of the new gem GitHub repo, e.g. NREL/openstudio-standards"
    echo "  4: Name of the GitHub branch to install, e.g. master"
    echo "  -- example use: ./set_standards_version.sh /usr/local/openstudio-2.7.1/Ruby openstudio-standards NREL/openstudio-standards master"
    exit 1
fi

echo $0

GEMFILE_DIR=$1
GEMFILE_PATH=${GEMFILE_DIR}/Gemfile
NEW_GEMFILE_DIR=/var/oscli
EXISTING_GEM=$2
NEW_GEM_REPO=$3
NEW_GEM_BRANCH=$4
GEMFILEUPDATE=$NEW_GEMFILE_DIR/analysis_$SCRIPT_ANALYSIS_ID.lock

# Verify the path of the required files
if [ ! -d "$GEMFILE_DIR" ]; then
  echo "Directory of Gemfile does not exist"
  exit 1
fi

if [ ! -f "$GEMFILE_PATH" ]; then
  echo "Gemfile does not exist in: ${GEMFILE_PATH}"
  exit 1
fi

# Making sure the right version of bundler is installed
gem install bundler -v 1.14.4

# First check if there is a file that indicates the gem has already been updated.
# We only need to update the bundle once / worker, not every time a data point is initialized.
echo "Checking if Gemfile has been updated in ${GEMFILEUPDATE}"
if [ -e $GEMFILEUPDATE ]
then
    echo "***The gem bundle has already been updated"
    exit 0
fi

mkdir -p $NEW_GEMFILE_DIR
# Gemfile for OpenStudio
NEW_GEMFILE=$NEW_GEMFILE_DIR/Gemfile

# Update gem definition in OpenStudio Gemfile
# Replace:
# gem 'openstudio-standards', '= 0.1.15'
OLDGEM="gem '$EXISTING_GEM'"
echo "***Replacing gem:"
echo "$OLDGEM"

# With this:
# gem 'openstudio-standards', github: 'NREL/openstudio-standards', branch: 'PNNL'
NEWGEM="gem '$EXISTING_GEM', github: '$NEW_GEM_REPO', branch: '$NEW_GEM_BRANCH'"
echo "***With gem:"
echo "$NEWGEM"

# Modify the reference Gemfile in place
cp $GEMFILE_DIR/Gemfile /var/oscli/
sed -i -e "s|$OLDGEM.*|$NEWGEM|g" $NEW_GEMFILE

# Pull the wfg from develop because otherwise `require 'openstudio-workflow'` fails
WFG="gem 'openstudio-workflow'"
NEWWFG="gem 'openstudio-workflow', github: 'NREL/openstudio-workflow-gem', branch: 'develop'"
echo "***Additionally,"
echo "***Replacing gem:"
echo "$WFG"
echo "***With gem:"
echo "$NEWWFG"
sed -i -e "s|$WFG.*|$NEWWFG|g" $NEW_GEMFILE

# Show the modified Gemfile contents in the log
cd $NEW_GEMFILE_DIR
dos2unix $NEW_GEMFILE
echo "***Here is the modified Gemfile:"
cat $NEW_GEMFILE

# Set & unset the required env vars
for evar in $(env | cut -d '=' -f 1 | grep ^BUNDLE); do unset $evar; done
for evar in $(env | cut -d '=' -f 1 | grep ^GEM); do unset $evar; done
for evar in $(env | cut -d '=' -f 1 | grep ^RUBY); do unset $evar; done

# Why are we setting HOME to /root and PATH. This should be set elsewhere, not in this script.
# export HOME=/root
# export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
# TODO: Check if we can remove /usr/Ruby... this feels historic.
# This will only set RUBYLIB for the context of this script, not sure this really works.
export RUBYLIB=$GEMFILE_DIR:/usr/Ruby:$RUBYLIB

# Update the specified gem in the bundle
echo "***Updating the specified gem:"
if [ -f Gemfile.lock ]; then
  rm Gemfile.lock
fi
bundle _1.14.4_ install --path gems

# Note that the bundle has been updated
echo >> $GEMFILEUPDATE
