# this is a quick and dirty migration of runemomniagg2.sh to the 
# --enable-demo mode of aggregate testing

function kill_netperfs {
    pkill -ALRM netperf

    pgrep -P 1 -f netperf > /dev/null
    while [ $? -eq 0 ]
    do
	sleep 1
	pgrep -P 1 -f netperf > /dev/null
    done
}

function run_cmd {

    NOW=`date +%s.%N`
    echo "Starting netperfs at $NOW for $TEST" | tee $TESTLOG
    i=0;

# the starting point for our load level pauses
    PAUSE_AT=1


    while [ $i -lt $MAX_INSTANCES ]
    do
	echo "Starting netperfs on localhost for $TEST" | tee -a $TESTLOG
	TARGET=${REMOTE_HOSTS[`expr $i % $NUM_REMOTE_HOSTS`]}
	$NETPERF -H $TARGET $NETPERF_CMD 2>&1 > netperf_${TEST}_to_${TARGET}_${i}.out &

    # give it a moment to get going
	sleep 1

	i=`expr $i + 1`

	if [ $i  -eq $PAUSE_AT ] && [ $i -ne $MAX_INSTANCES ]
	then
	    NOW=`date +%s.%N`
	    echo "Pausing for $DURATION seconds at $NOW with $i netperfs running for $TEST" | tee -a $TESTLOG
	    sleep $DURATION
	    PAUSE_AT=`expr $PAUSE_AT \* 2`
	    NOW=`date +%s.%N`
	    echo "Resuming at $NOW for $TEST" | tee -a $TESTLOG
	fi    
    done

    NOW=`date +%s.%N`
    echo "Netperfs started by $NOW for $TEST" | tee -a $TESTLOG

#wait for our test duration
    sleep $DURATION

#kludgey but this sleep should mean that another interim result will be emitted
    sleep 3

# stop all the netperfs
    NOW=`date +%s.%N`
    echo "Netperfs stopping $NOW for $TEST" | tee -a $TESTLOG
    kill_netperfs
    
    NOW=`date +%s.%N`
    echo "Netperfs stopped $NOW for $TEST" | tee -a $TESTLOG

}

# here then is the "main" part

if [ ! -f ./remote_hosts ]
then
    echo "This script requires a remote_hosts file"
    exit -1
fi
. ./remote_hosts

# how many processors are there on this system
NUM_CPUS=`grep processor /proc/cpuinfo | wc -l`

# the number of netperf instances we will run will be up to 2x the
# number of CPUs
MAX_INSTANCES=`expr $NUM_CPUS \* 2`

NETPERF=${NETPERF:="./netperf"}

if [ $NUM_REMOTE_HOSTS -lt 2 ]
then
    echo "The list of remote hosts is too short.  There must be at least 2."
    exit -1
fi

# we assume that netservers are already running on all the load generators

DURATION=120
MY_UUID=`uuidgen`
LENGTH="-l 7200"
OUTPUT="-o all"

# TCP_RR for TPC/PPS using single-byte transactions and TCP_NODELAY
TEST="tps"
TESTLOG="netperf_tps.log"
NETPERF_CMD="-D 1 -c -C -f x -P 0 -t omni $LENGTH -v 2 -- -r 1 -b 8 -D -u $MY_UUID $OUTPUT"
run_cmd

# Bidirectional using burst-mode TCP_RR and large request/response size
TEST="bidirectional"
TESTLOG="netperf_bidirectional.log"
NETPERF_CMD="-D 1 -c -C -f m -P 0 -t omni $LENGTH -v 2 -- -r 64K -s 1M -S 1M -b 12 -u $MY_UUID $OUTPUT"
run_cmd

# TCP_STREAM aka outbound with a 64K send size
TEST="outbound"
TESTLOG="netperf_outbound.log"
# the netperf command is everything but netperf -H mumble
NETPERF_CMD="-D 1 -c -C -f m -P 0 -t omni $LENGTH -v 2 -- -m 64K -u $MY_UUID $OUTPUT"
run_cmd

# TCP_MAERTS aka inbound with a 64K send size - why is this one last?
# because presently when I pkill the netperf of a "MAERTS" test, the
# netserver does not behave well and it may not be possible to get it
# to behave well.  but we will still have all the interim results even
# if we don't get the final results, the useful parts of which will be
# the same as the other tests anyway
TEST="inbound"
TESTLOG="netperf_inbound.log"
NETPERF_CMD="-D 1 -c -C -f m -P 0 -t omni $LENGTH -v 2 -- -m ,64K -u $MY_UUID $OUTPUT"
run_cmd
