#!/usr/bin/env bash

# Stop on any error
set -e

# Needed for building Python libraries
pkgin -y install gcc7 git-base

export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Needed to configure 'LC_ALL=en_US.UTF-8' and such.
source /etc/profile

pushd /home/zulip

# The location '/srv' is recommended by Zulip. Things might work incorrectly if this location isn't used.
/opt/local/bin/virtualenv-3.5 /srv/zulip-py3-venv -p python3

# Activate Python 3 virtual environment.
source /srv/zulip-py3-venv/bin/activate

# Upgrade pip itself because older versions have known issues.
pip install --upgrade pip 
# Install the required Python packages.
pip install --no-deps -r requirements/prod.txt

popd

pkgin -y remove gcc7 git-base

