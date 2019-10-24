#!/usr/bin/env bash

# Script used by Consul template to restart / refresh various Zulip related services. Used when
# configuration changes.

# If a service is in maintenance state we will clear it after trying to restart it. Clearing the maintenance 
# state will result in the service being (re)started anyway if it was in maintenance state.
#
# '|| true' is appended because don't want the script to die or return a fault code if any of these command
# return an non zero exit code. Which it will always do because either restart or clear will succeed but not both.

echo "You can safely ignore warnings about 'Instance \"svc:/foo\" is not in a maintenance or degraded state.'"

# Correct permissions so processes in the 'zulip' group can read the config file.
chown consul_t:zulip /etc/zulip/settings.py

# Web app
/usr/sbin/svcadm restart zulip/django-uwsgi || true
/usr/sbin/svcadm clear zulip/django-uwsgi || true

# Push notifications 
/usr/sbin/svcadm restart zulip/tornado || true
/usr/sbin/svcadm clear zulip/tornado || true

# Queue processor
/usr/sbin/svcadm restart zulip/queue-processor || true
/usr/sbin/svcadm clear zulip/queue-processor || true

# Full text update processor
/usr/sbin/svcadm restart zulip/process-fts-updates || true
/usr/sbin/svcadm clear zulip/process-fts-updates || true