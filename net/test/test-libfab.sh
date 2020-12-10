#!/usr/bin/env bash
set -xeu

# Command line example (for one host)
# sudo ./test-user.sh console localhost localhost localhost \
#		      0@lo 0@lo 0@lo ping 100000 4k 8 4

if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root"
    exit 1
fi

if [ $# -ne 7 -a $# -ne 12 ]; then
	echo "Usage: `basename $0` script_role console_cr server_cr client_cr" \
	     "console_if server_if client_if" \
	     "[test_type msg_nr msg_size concurrency_server concurrency_client]"
	echo "where"
	echo "  script_role	-" \
	     "one of [console|server|client]"
	echo "  *_cr		-" \
	     "credentials to run test console/server/client (username@hostname)"
	echo "  *_if		-" \
	     "LNET interface for test console (e.g. 172.18.50.161@o2ib)"
	exit
fi

if [ $1 != "console" -a $1 != "server" -a $1 != "client" ]; then
	echo "Invalid script role $1. Should be one of [console|server|client]"
	exit
fi

. /home/743690/work/libfab/test_framework/intergate/cortx-motr/m0t1fs/linux_kernel/st/common.sh

unload_all() {
    modunload
    modunload_galois
}
trap unload_all EXIT

modload_galois
modload || exit $?

JOB_IDS=
SCRIPT=/home/743690/work/libfab/test_framework/intergate/cortx-motr/net/test/test-libfab.sh

PID=12345
PORTAL=42

ROLE=$1
CONSOLE_CR=$2
SERVER_CR=$3
CLIENT_CR=$4
CONSOLE_IF=$5
SERVER_IF=$6
CLIENT_IF=$7
TEST_TYPE=$8
MSG_NR=$9
MSG_SIZE=${10}
CONCUR_SERVER=${11}
CONCUR_CLIENT=${12}
COMMON_PARAMS="$2 $3 $4 $5 $6 $7"
shift 7

job_id_add() {
	JOB_IDS="$JOB_IDS $!"
}

run_console() {
        echo "type : $TEST_TYPE msg_nr : $MSG_NR msg_size : $MSG_SIZE con-ser : $CONCUR_SERVER con-cli : $CONCUR_CLIENT"
	/home/743690/work/libfab/test_framework/intergate/cortx-motr/net/test/user_space/m0nettest \
		-t $TEST_TYPE \
		-n $MSG_NR \
		-s $MSG_SIZE \
		-E $CONCUR_SERVER \
		-e $CONCUR_CLIENT \
		-A "$CONSOLE_IF:100" \
		-a "$CONSOLE_IF:101" \
		-C "$SERVER_IF:200" \
		-c "$CLIENT_IF:300" \
		-D "$SERVER_IF:236" \
		-d "$CLIENT_IF:248" &
	job_id_add
}

run_server() {
	/home/743690/work/libfab/test_framework/intergate/cortx-motr/net/test/user_space/m0nettestd \
		-a "$SERVER_IF:200" \
		-c "$CONSOLE_IF:100" &
	job_id_add
}

run_client() {
	/home/743690/work/libfab/test_framework/intergate/cortx-motr/net/test/user_space/m0nettestd \
		-a "$CLIENT_IF:300" \
		-c "$CONSOLE_IF:101" &
	job_id_add
}

run_ssh() {
	ssh $* &
	job_id_add
}
if [ "$ROLE" = "console" ]; then

	if [ "$CONSOLE_CR" = "$SERVER_CR" ]; then
		# test server on the host with test console
		run_server
	else
		# test server on the some other host
		run_ssh "$SERVER_CR" "$SCRIPT server $COMMON_PARAMS"
	fi
	if [ "$CONSOLE_CR" = "$CLIENT_CR" ]; then
		# test client on the host with test console
		run_client
	else
		# if test client on the node with test server then don't run
		# script over ssh again
		if [ "$SERVER_CR" != "$CLIENT_CR" ]; then
			run_ssh "$CLIENT_CR" "$SCRIPT client $COMMON_PARAMS"
		fi
	fi
	# time to initialize nodes - magic number
	sleep 3
	run_console
fi

if [ "$ROLE" = "server" ]; then
	if [ "$SERVER_CR" = "$CLIENT_CR" ]; then
		run_client
	fi
	run_server
fi

if [ "$ROLE" = "client" ]; then
	run_client
fi

wait $JOB_IDS
