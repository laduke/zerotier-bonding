
export BASE_DIR=/root/zerotiers
export NETWORKID=""
export IP=10.1.1.2/24
export MAC=02:22:22:22:22:26
export NUM_ZT=`nproc`

set -e

setup__zt () {
	if [ -z "${NETWORKID}" ]; then
    echo "Please set NETWORKID at the top of this file"
	exit
	fi

	for i in `seq ${NUM_ZT}`; do
		echo mkdir -p $BASE_DIR/node${i};
	done

	for i in `seq ${NUM_ZT}`; do
		echo "echo $NETWORKID=zt-node${i} > ${BASE_DIR}/node${i}/devicemap"
	done

	for i in `seq ${NUM_ZT}`; do
		# echo zerotier-one -U -d -p199${i}3 ${BASE_DIR}/node${i}/;
		core=$(expr $i - 1)
		echo taskset -c ${core} "zerotier-one -U -d -p199${i}3 ${BASE_DIR}/node${i}/;"
	done

	echo sleep 5

	for i in `seq ${NUM_ZT}`; do
		echo zerotier-cli -D${BASE_DIR}/node${i} join $NETWORKID
	done

	for i in `seq ${NUM_ZT}`; do
		echo "zerotier-cli -D${BASE_DIR}/node${i} set $NETWORKID allowManaged=0 > /dev/null"
	done

	for i in `seq ${NUM_ZT}`; do
		echo "alias z${i}=\"zerotier-cli -D${BASE_DIR}/node${i}\""
	done
}

setup__bond () {
	echo "ip link add zt-bond type bond miimon 100 mode balance-alb xmit_hash_policy 1"

	for i in `seq ${NUM_ZT}`; do
		echo ip link set zt-node${i} down
		echo ip link set nomaster zt-node${i}
	done

	echo ip link set zt-bond down
	echo ip link set zt-bond type bond miimon 100 mode balance-rr xmit_hash_policy 1

	for i in `seq ${NUM_ZT}`; do
		echo ip link set zt-node${i} master zt-bond
	done

	for i in `seq ${NUM_ZT}`; do
		echo ip link set zt-node${i} up
	done

	echo ip link set zt-bond address $MAC
	echo ip addr add $IP dev zt-bond
	echo ip link set zt-bond up
j

setup__all () {
	echo "set -x"
	setup__zt
	setup__bond
	echo "sleep 5"
	setup__bridging
}

remove__bond () {
	echo ip link set zt-bond down

	for i in `seq ${NUM_ZT}`; do
		echo ip link set zt-node${i} down
		echo ip link set nomaster zt-node${i}
		echo ip link delete zt-node${i}
	done

	echo ip link delete zt-bond
}




setup__bridging () {
for i in `seq ${NUM_ZT}`; do
	ID=$(cat ${BASE_DIR}/node${i}/identity.public | cut -d":" -f 1)
	echo curl -s -X POST -H \"Authorization: token \$\(cat token\)\" https://api.zerotier.com/api/v1/network/$NETWORKID/member/$ID -d \
		\'{ \"name\": \"bond-node-${i}\", \"config\": { \"activeBridge\": true }}\' \> /dev/null 
done
}


if declare -f "${1}__$2" >/dev/null; then
	func="${1}__$2"
	shift; shift    # pop $1 and $2 off the argument list
	"$func" "$@"    # invoke our named function w/ all remaining arguments
elif declare -f "$1" >/dev/null 2>&1; then
	"$@"
else
	echo "This script doesn't run commands. It echos command that you can then run"
	echo "Edit the variables at the top. Then run ./script.sh setup all > my-script.sh"
	echo "Then inspect my-script.sh and then run _it_ if you want."
	echo "./script.sh setup all | bash works too"
	echo "Then rewrite this script as a proper script. Thanks"
	#echo "Neither function $1 nor subcommand ${1}__$2 recognized" >&2
	exit 1
fi

