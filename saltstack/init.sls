# TODO: 
# - Configure Camo (SSL image proxy). Should probably run this in a separate VM.
# - Configure Mobile push ( https://zulip.readthedocs.io/en/latest/prod-mobile-push-notifications.html )
# - Configure federated authentication (OpenID, SAML).

# Low Prio TODO:
# 
# - RabbitMQ uses the guest/guest login. Since it is only accessible inside the VM (localhost) its not that big a deal.

# - We run Zulip primarily with Python 3 (is now the default starting from Zulip 1.7.0). 
# - We use PGroonga instead of the (currently default) builtin PostgreSQL tsearch. PGroonga supports multiple 
#   languages (like Dutch) and will become the default search for Zulip.
#
# Zulip is quite a complex application to configure / install. 
#
# This image creation config is based on the non-Vagrant development installation documentation:
# https://zulip.readthedocs.io/en/1.8.0/development/setup-advanced.html. We can't use the normal installation scripts
# because everything assumes you are using (Ubuntu) Linux.
# 
# Bear in mind that the development documentation is about configuring a development environment. This means you don't
# need to run 'npm install', no './tools/setup/emoji/build_emoji', etc. All these things are already in the 
# '/prod-static/' directory of the Zulip release tarball.
#
# At the start we used 12factor's Vault integration with Django. This worked pretty well. However we replaced it
# with "standard" consul template integration (generating config files) because Zulip consists of a lot a separate
# app's which all read the settings.py app and expect to find their login details there. Also when running
# the 'manage.py' app for simple administrative task you needed to obtain Vault credentials.

include:
  - consul-template
  - stolon-proxy
  - nginx
  # TODO: Have Zulip use Ambry as file storage (T1083).
  - restic-robot

Install Zulip required packages:
  pkg.installed:
    - pkgs:
      # Node version from '/home/zulip/scripts/lib/install-node'
      - nodejs: '>=6.11.0' 
      - libjpeg-turbo
      - libffi
      - memcached
      - rabbitmq
      - openldap-client
      - python35
      - py35-virtualenv
      - py35-lxml
      - py35-libxml2
      - py35-cElementTree
      - redis
      - postgresql96-client
      - libmemcached
      - freetype-lib
      - libxml

Create Zulip group:
  group.present:
    - name: zulip

Create Zulip user:
  user.present:
    - name: zulip
    - fullname: Zulip
    - gid: zulip
    - shell: /bin/bash
    - home: /home/zulip
    - createhome: False
    - require:
      - group: zulip  
  
# WARNING! When updating Zulip also update the 'zulip/settings.py' file in this salt configuration. See the top
#          of the file for instructions.
Extract Zulip Tarball:
  archive.extracted:
    # Usually we would install Zulip in /opt (so '/opt/zulip') however a lot of defaults in Zulip assume Zulip is 
    # installed in '/home/zulip'. So in order to make our lives easier we just go with the flow.
    - name: /home/zulip
    - user: root
    - group: zulip
    - source: http://misc.serviceplanet.nl/zulip/2.0.2/zulip-server-2.0.2.tar.gz
    - archive_format: tar
    - options: --strip-components=1
    - enforce_toplevel: False
    - source_hash: sha512=e3b9e9304cc4927d74f94633769def8d461c138dce26707952f0f1789a48879921a24c3a93788a2e6ac5fb40750f0fb9229b6c802bac91ee5f31336d3688062b
    - require:
      - group: zulip

# epoll is a Linux specific system call. Replace it with the Solaris equivalent.
/home/zulip/zerver/tornado/ioloop_logging.py:
  file.patch:
    - source: salt://zulip/files/zulip/ioloop_logging_py_solaris.patch
    - strip: 1
    - hash: sha512:0cf138ca86366c4cb91681eccc9297427555d349ea806d90c1b1a9c9715bfd976f5ebf733f137e49c276a741a97deff1a200e61fd0c8722c0fa510063a6d662d
    - require:
      - Extract Zulip Tarball

# Don't execute the tsearch update statement when using pgroonga. It causes an error on our PostgreSQL server
# because we haven't installed the dictionaries. Those aren't part of the default PostgreSQL pkgsrc package. Also
# we don't use tsearch, we use pgroonga.
/home/zulip/puppet/zulip/files/postgresql/process_fts_updates:
  file.patch:
  - source: salt://zulip/files/zulip/process_fts_updates.patch
  - strip: 1
  - hash: sha512:7b2884b31d8552cb76c44b08f21600b1ae8c1a48cd3dfbf0430f5ad0f427237de34bb8a56ed97a2d548a8bb2af7d824336e38908ac87f2ae6b1c22aa74f72b1e
  - require:
    - Extract Zulip Tarball

# In this commit: https://github.com/zulip/zulip/pull/9595/commits/b9c5798caf0d2b7603c6efc9cf38e1762a1059ce pgroonga support
# was migrated to pgroonga V2. Oddly enough pgroonga is now called like this "func.pgroonga_match_positions_character".
# Notice the underscore between the schema (pgroonga) and the actual function name (match_positions_character). No matter
# what I tried with 'search_path' etc. I could not make it work with the new notation. This patch reverts the new notation.
/home/zulip/zerver/views/messages.py:
  file.patch:
  - source: salt://zulip/files/zulip/pgroonga_namespace.patch
  - strip: 1
  - hash: sha512:73d6bc8cf7b28d7bfcf2a9e7754b7fb9e33fa85930fe076c5d73429a73d7e0620944f7680c918aebd6566c042c7c2b36ba42c2a0f7208a1504423eb5796439ed
  - require:
    - Extract Zulip Tarball

# Patch settings.py
#
# - We disable logging to files so we don't have to manually rotate them (if they grow too large). 
#   All logging goes to console which ends up in SMF (and is automagically rotated).
# - We remove all database config so we can redefine it in '/etc/zulip.settings.py'.
/home/zulip/zproject/settings.py:
  file.patch:
    - source: salt://zulip/files/zulip/settings_py.patch
    - strip: 1
    - hash: sha512:ced9d0a08aabc3b871b8233744d2260faf70887bce5adf60783915311ea28a816d442e645468332864c16670955381d76c56b15868d7ce229fe7e1960c8131ac
    - require:
      - Extract Zulip Tarball
      
# Patch prod.txt
#
# - UWSGi 2.0.16 introduced a bug which causes the build on Solaris to fail. PR has been submitted and future versions should
#   be fixed: https://github.com/unbit/uwsgi/pull/1778
#
# Used to be broken in 1.8.1 but fixed in upstream libraries (here in case breakage comes back):
# - psycopg2 broke Illumos and Solaris 11 support in 2.7.4. To be fixed with: https://github.com/psycopg/psycopg2/pull/678
/home/zulip/requirements/prod.txt:
  file.patch:
    - source: salt://zulip/files/zulip/prod_txt.patch
    - strip: 1
    - hash: sha512:d675e35ec00a0885946c7a3c1f3f1cbd97c223b7c24adb0727bf20019cb67e86b57e55ff716bbd909363d1c7516adeeaad5827d0d8adb28ce1aa3c446ea3dd0b
    - require:
      - Extract Zulip Tarball

# All static content is in a subdir of 'prod-static' called 'serve'. However Zulip expects to find it directly under 'prod-static'.
Move Zulip static content to correct location:
  cmd.run:
    - name: mv /home/zulip/prod-static/serve/* /home/zulip/prod-static/
    - require:
      - Extract Zulip Tarball

# Zulip expects this directory to exists. For example cache.py does: 
# subprocess.check_call(["mkdir", "-p", os.path.join(settings.DEPLOY_ROOT, "var")])
/home/zulip/var:
  file.directory:
    - user: root
    - group: zulip
    - file_mode: 640
    - dir_mode: 770
    - makedirs: True
    - recurse:
      - user
      - group
      - mode   
      
# Zulip expects to find this file. 
# See: https://zulip.readthedocs.io/en/latest/settings.html for more information about where Zulip searches 
# for config files.
/home/zulip/zproject/prod_settings.py:
  file.symlink:
    - target: /etc/zulip/settings.py
    - require:
      - Extract Zulip Tarball

/usr/local/bin/zulip-settings-changed.sh:
  file.managed:
    - source: salt://zulip/files/consul-template/zulip-settings-changed.sh
    - user: root
    - group: root
    - mode: 755

/etc/zulip:
  file.directory:
    - user: zulip
    - group: consul_t
    # Consul template needs to be able to write in this directory.
    - file_mode: 660
    - dir_mode: 770
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

/etc/zulip/uwsgi.ini:
  file.managed:
    - source: salt://zulip/files/uwsgi/uwsgi.ini
    - user: zulip
    - group: zulip
    - requires:
      - /etc/zulip
      
/etc/nginx/zulip-include:
  file.directory:
    - user: nginx
    - group: nginx
    - file_mode: 640
    - dir_mode: 750
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

/var/log/zulip:
  file.directory:
    - user: zulip
    - group: zulip
    - file_mode: 660
    - dir_mode: 770
    - makedirs: True
    - recurse:
      - user
      - group
      - mode
      
/var/zulip/uploads/files:
  file.directory:
    - user: zulip
    - group: zulip
    - file_mode: 640
    - dir_mode: 750
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

/var/zulip/local-static:
  file.directory:
    - user: zulip
    - group: zulip
    - file_mode: 640
    - dir_mode: 750
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

/var/zulip/uploads/avatars:
  file.directory:
    - user: zulip
    - group: zulip
    - file_mode: 640
    - dir_mode: 750
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

# Logging is normally disabled / toned down but we also configure logadm to rotate the logs.
/etc/logadm.d/zulip.conf:
  file.managed:
    - source: salt://zulip/files/logadm/zulip.conf
    - user: root
    - group: sys

Create Python 3 virtual environment:
  cmd.script:
    - name: salt://zulip/scripts/install_python_3_env.sh
    - requires:
      - /home/zulip/requirements/prod.txt
      - Install packages required to build Python packages
      - Install Zulip required packages
      - Extract Zulip Tarball

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://zulip/files/nginx/nginx.conf
    - user: nginx
    - group: nginx

/etc/nginx/zulip-include/proxy:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/proxy
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/zulip-include/proxy_longpolling:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/proxy_longpolling
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/zulip-include/location-sockjs:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/location-sockjs
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/zulip-include/uploads.types:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/uploads.types
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/zulip-include/app:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/app
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/zulip-include/upstreams:
  file.managed:
    - source: salt://zulip/files/nginx/zulip-include/upstreams
    - user: nginx
    - group: nginx
    - requires:
      - /etc/nginx/zulip-include

/etc/nginx/uwsgi_params:
  file.managed:
    - source: salt://zulip/files/nginx/uwsgi_params
    - user: nginx
    - group: nginx

# Needed so NGINX can access the web root and uWSGI socket.
Add nginx user to zulip group:
  cmd.run:
    - name: usermod -G zulip,nginx nginx

# This is for example used by Consul template to restart uWSGI running the Zulip Django webapp.
Add Zulip authorizations:
  file.append:
    - name: /etc/security/auth_attr
    - text: 
      - "solaris.smf.manage.zulip:::Manage Zulip Services::help=SmfWusbStates.html"

# Allows restart of various Zulip services by Consul template.
Allow Consul Template Zulip service management:
  cmd.run:
    - name: usermod -A solaris.smf.manage.zulip consul_t
    - require:
      - Add Zulip authorizations

Install settings.py Consul template configuration:
  file.managed:
    - name: /etc/consul-template/conf.d/200-zulip-settings-py.hcl
    - source: salt://zulip/files/consul-template/settings.py.hcl
    - user: root
    - group: consul_t
    - mode: 640

# Zulip Django / uWSGI SMF Manifest

/lib/svc/manifest/site/zulip-django-uwsgi:
  file.managed:
    - source: salt://zulip/files/smf/zulip-django-uwsgi
    - user: root
    - group: sys
    - mode: 755

/lib/svc/manifest/site/zulip-django-uwsgi.xml:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - source: salt://zulip/files/smf/zulip-django-uwsgi.xml

Import Zulip Django uWSGI SMF Manifest:
  cmd.run:
    - name: svccfg import /lib/svc/manifest/site/zulip-django-uwsgi.xml
    - require:
      - file: /lib/svc/manifest/site/zulip-django-uwsgi.xml
      - file: Add Zulip authorizations

# Zulip Tornado (push notifications) SMF Manifest      
      
/lib/svc/manifest/site/zulip-tornado:
  file.managed:
    - source: salt://zulip/files/smf/zulip-tornado
    - user: root
    - group: sys
    - mode: 755

/lib/svc/manifest/site/zulip-tornado.xml:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - source: salt://zulip/files/smf/zulip-tornado.xml

Import Zulip Tornado SMF Manifest:
  cmd.run:
    - name: svccfg import /lib/svc/manifest/site/zulip-tornado.xml
    - require:
      - file: /lib/svc/manifest/site/zulip-tornado.xml
      - file: Add Zulip authorizations 

# Zulip Full text update processor
/lib/svc/manifest/site/zulip-process-fts-updates:
  file.managed:
    - source: salt://zulip/files/smf/zulip-process-fts-updates
    - user: root
    - group: sys
    - mode: 755

/lib/svc/manifest/site/zulip-process-fts-updates.xml:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - source: salt://zulip/files/smf/zulip-process-fts-updates.xml

Import Zulip Process Full Text Search SMF Manifest:
  cmd.run:
    - name: svccfg import /lib/svc/manifest/site/zulip-process-fts-updates.xml
    - require:
      - file: /lib/svc/manifest/site/zulip-process-fts-updates.xml
      - file: Add Zulip authorizations

# Zulip uses a whole bunch of queue processors.
# See https://github.com/zulip/zulip/blob/master/docs/queuing.md for more information. 
# we run them multi-threaded instead of multi process since it is easier to manage.
/lib/svc/manifest/site/zulip-queue-processor.xml:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - source: salt://zulip/files/smf/zulip-queue-processor.xml         

Import Zulip queue processor SMF Manifest:
  cmd.run:
    - name: svccfg import /lib/svc/manifest/site/zulip-queue-processor.xml
    - require:
      - file: /lib/svc/manifest/site/zulip-queue-processor.xml
      - file: Add Zulip authorizations 

/lib/svc/manifest/site/zulip-queue-processor:
  file.managed:
    - source: salt://zulip/files/smf/zulip-queue-processor
    - user: root
    - group: sys
    - mode: 755
