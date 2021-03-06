#!/usr/bin/env bash

# This script will run 'mod_wsgi-express start-server', adding in some
# additional initial arguments to send logging to the terminal and to
# force the use of port 80. If necessary the port to use can be overridden
# using the PORT environment variable.

# Mark what runtime this is.

WHISKEY_RUNTIME=openshift
export WHISKEY_RUNTIME

# Set up the home directory for the application.

WHISKEY_HOMEDIR=$OPENSHIFT_REPO_DIR
export WHISKEY_HOMEDIR

# Set up the bin directory where our scripts will be.

WHISKEY_BINDIR=$VIRTUAL_ENV/bin
export WHISKEY_BINDIR

# Override LD_LIBRARY_PATH so shared libraries can be found.

LD_LIBRARY_PATH=$WHISKEY_HOMEDIR/.whiskey/apr/lib:$LD_LIBRARY_PATH
LD_LIBRARY_PATH=$WHISKEY_HOMEDIR/.whiskey/apr-util/lib:$LD_LIBRARY_PATH

export LD_LIBRARY_PATH

# Set up the user_vars directory where environment variable updates
# can be done.
#
# Note that every gear will have their own copy of the home directory so
# we do not have to worry about them interfering with each other. We can
# therefore use the user_vars directory as the environment directory.

WHISKEY_ENVDIR=$WHISKEY_HOMEDIR/.whiskey/user_vars
export WHISKEY_ENVDIR

# Make sure we are in the correct working directory for the application.

cd $WHISKEY_HOMEDIR

# OpenShift will have passed through any environment variables set in the
# OpenShift config. Here we are going to look for any statically defined
# environment variables provided by the user as part of the actual
# application. These will have been placed in the '.whiskey/user_vars'
# directory. The name of the file corresponds to the name of the
# environment variable and the contents of the file the value to set the
# environment variable to. Each of the environment variables is set and
# exported.

envvars=

for name in `ls .whiskey/user_vars`; do
    export $name=`cat .whiskey/user_vars/$name`
    envvars="$envvars $name"
done

# Run any user supplied script to be run to set, modify or delete the
# environment variables.

if [ -x .whiskey/action_hooks/deploy-env ]; then
    echo " -----> Running .whiskey/action_hooks/deploy-env"
    .whiskey/action_hooks/deploy-env
fi

# Go back and reset all the environment variables based on additions or
# changes. Unset any for which the environment variable file no longer
# exists, albeit in practice that is probably unlikely.

for name in `ls .whiskey/user_vars`; do
    export $name=`cat .whiskey/user_vars/$name`
done

for name in $envvars; do
    if test ! -f .whiskey/user_vars/$name; then
        unset $name
    fi
done

# Run any user supplied script to be run prior to starting the
# application in the actual container. The script must be executable in
# order to be run.

if [ -x .whiskey/action_hooks/deploy ]; then
    echo " -----> Running .whiskey/action_hooks/deploy"
    .whiskey/action_hooks/deploy
fi

# Now run the the actual application under Apache/mod_wsgi. This is run
# in the foreground, replacing this process and adopting its process ID
# so that signals are received properly and Apache will shutdown
# properly when the container is being stopped.
#
# Because each gear has its own copy of the Python virtual environment,
# and it lives at a different directory, we need to override the locations
# of the Apache executables as the cached paths for them in the Python
# package for mod_wsgi-express will be wrong.

SERVER_ROOT=$OPENSHIFT_PYTHON_DIR/run/mod_wsgi

PIDFILE=$OPENSHIFT_PYTHON_DIR/run/appserver.pid

HTTPD=$WHISKEY_BINDIR/httpd
ROTATELOGS=$WHISKEY_BINDIR/rotatelogs
MODULES_DIRECTORY=$WHISKEY_HOMEDIR/.whiskey/apache/modules

HOST=$OPENSHIFT_PYTHON_IP
PORT=$OPENSHIFT_PYTHON_PORT

SERVER_ARGS="--server-root $SERVER_ROOT"
SERVER_ARGS="$SERVER_ARGS --httpd-executable $HTTPD"
SERVER_ARGS="$SERVER_ARGS --rotatelogs-executable $ROTATELOGS"
SERVER_ARGS="$SERVER_ARGS --modules-directory $MODULES_DIRECTORY"
SERVER_ARGS="$SERVER_ARGS --python-eggs $PYTHON_EGG_CACHE"
SERVER_ARGS="$SERVER_ARGS --log-to-terminal --host $HOST --port $PORT"

if test x"$NEW_RELIC_LICENSE_KEY" != x"" -o \
            x"$NEW_RELIC_CONFIG_FILE" != x""; then
    SERVER_ARGS="$SERVER_ARGS --with-newrelic"
fi

exec mod_wsgi-express start-server $SERVER_ARGS "$@"
