#!/bin/bash
#230223

set -eu


RUN_SCRIPT=$(realpath $0)
WORKER_SCRIPT=$(dirname $RUN_SCRIPT)/worker.sh
NODELIST=(
    bnode0
    bnode1
    bnode2
    bnode3
    bnode4
    bnode5
    bnode6
    bnode7
    bnode8
    bnode9
    bnode10
    bnode11
    bnode12
    bnode13
    bnode14
    bnode15
    bnode16
)

declare -A defaultargs
defaultargs[cutoff]=0.9
defaultargs[interval]=5

function usage {
	cat <<-EOF
		Kills all processes of the user with the most memory usage.

		Arguments:
			--logdir : directory where logs will be written. One log file is created for each node.
			--cutoff : [OPTIONAL] Threshold memory usage fraction. Default: ${defaultargs[cutoff]}
			--interval : [OPTIONAL] Monitoring interval in seconds. Default: ${defaultargs[interval]}
	EOF
	exit 1
}


function argparse {
	required_args=(
		logdir
	)

	# main
	declare -gA args
	if [[ $# = 0 ]] ; then
		usage
	else
		while [[ $# -gt 0 ]] ; do
			case "$1" in
				--logdir)
					shift ; args[logdir]="$1" ; shift ;;
				--cutoff)
					shift ; args[cutoff]="$1" ; shift ;;
				--interval)
					shift ; args[interval]="$1" ; shift ;;
				-h|--help|*)
					usage ;;
			esac
		done
	fi

	# setting default args
	for key in ${!defaultargs[@]} ; do
		args[$key]=${args[$key]:-${defaultargs[$key]}}
	done

	# check if required arguments are all set
	for key in ${required_args[@]:-} ; do
		if [[ -z ${args[$key]:-} ]] ; then
			echo "Required argument --${key} is not set."
			exit 1
		fi
	done
	
	# sanity check

    # postprocess
    args[logdir]=$(realpath -s ${args[logdir]})
    mkdir -p ${args[logdir]}
}


function rootwarn {
	if [[ $USER != root ]] ; then
		cat <<-EOF
			Only root user may run this script.
		EOF
		exit 1
	fi
}


function node_job {
	nodename=$1
	while true; do
		echo [$(date)] $nodename instance turned ON
        remotecmd="bash ${WORKER_SCRIPT} --cutoff ${args[cutoff]} --interval ${args[interval]} >> ${args[logdir]}/${nodename}.log "
		ssh -t -t $nodename "$remotecmd"
		echo [$(date)] $nodename instance turned OFF

        sleep 10
	done
}


# main
argparse "$@"
rootwarn
trap 'kill 0' SIGINT SIGTERM SIGKILL

for nodename in "${NODELIST[@]}" ; do
	node_job $nodename &
done

wait

