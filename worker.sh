#!/usr/bin/bash
# by pjh
# 220908
	# v5 init
	# prints CMD of processes killed
	# wrote functions "print_processes_to_kill" and "get_maxuser"
# 230223
	# added argparse and set -eu

set -eu

declare -A defaultargs

function usage {
	cat <<-EOF
		Arguments:
			--cutoff : Threshold memory usage fraction.
			--interval : Monitoring interval in seconds.
	EOF
	exit 1
}


function argparse {
	required_args=(
		cutoff
		interval
	)

	# main
	declare -gA args
	if [[ $# = 0 ]] ; then
		usage
	else
		while [[ $# -gt 0 ]] ; do
			case "$1" in
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
}


function get_memuse {
	free | awk 'NR==2 {memuse = (1 - ($NF/$2)) ; print memuse}'
}


function print_processes_to_kill {
	# $1: user name
	# Lists up all processes of the user, excluding -bash and tmux, then prints process information to stdout, and pid to stderr
	# pids can be selectively redirected to a subprocess for killing
	ps -u $1 -o pid,rss,pmem,pcpu,cmd | 
		awk '
		NR==1{ print > "/dev/stdout" }
		NR>=2{ 
			n = split($0, fields, " ", seps)
			cmd = "" ; for (i=5;i<=n;i++) { cmd = cmd fields[i] seps[i] }
			pid = fields[1]
			if (!(cmd == "-bash" || cmd == "tmux")) {  # omits -bash or tmux
				print $0 > "/dev/stdout"
				print pid > "/dev/stderr"
			}
		}'
}


function get_maxuser {
	ps -A -o rss,user | 
		awk '
		NR >= 2 {
			user = $2
			rss = $1
			if (user != "root") { 
				memuse[user] += rss 
			}
		}
		END {
			PROCINFO["sorted_in"] = "@val_num_desc"
			for (user in memuse) {
				print user
				break
			}
		}'
}


function killsome {
	maxuser="$1"

	# message to user
	homedir=$(eval echo ~${maxuser})
	bashrc=${homedir}/.bashrc
	notifier=${homedir}/.memwatchdog_notifier
	inserted_line="source $notifier"

	#sed '/.welcome123/d' -i /home/users/${maxuser}/.bashrc
	sed "\&^${inserted_line}$&d" -i $bashrc
	echo "$inserted_line" >> $bashrc

	cat <<-EOF > $notifier
		date
		echo "@@@ YOUR PROCESSES WERE KILLED BY MEMORY WATCHDOG @@@"
		echo
		echo "- Due to limited memory resource, we set upper limit of memory usage of SLURM jobs as"
		echo "  ~ 6 GB per requested core."
		echo "- If your job occupies maximum of 15 GB of memory, you should run "
		echo "  sbatch requring at least 3 cores. (arguments: "-N 1 -n 1 -c 3")"
		echo "- Please confirm peak memory usage of the job you are going to submit,"
		echo "  then require adequate number of cores."
		echo

		sed "\&^${inserted_line}$&d" -i $bashrc
	EOF
	
	# log
	cat <<-EOF
	======================================
	$(date)

	Output of "free" command:
	$(free)

	Maxium usage user: ${maxuser}

	Sending SIGTERM to the following processes:

	EOF
	print_processes_to_kill ${maxuser} 2> >(
		while read pid ; do
			if ps -p $pid > /dev/null ; then
				kill -s 15 $pid
			fi
		done
	)
	echo

	sleep 10

	echo Sending SIGKILL to the following processes:
	echo
	print_processes_to_kill ${maxuser} 2> >(
		while read pid ; do
			if ps -p $pid > /dev/null ; then
				kill -s 9 $pid
			fi
		done
	)
	echo
	echo ======================================

	sleep 10
}


# main
argparse "$@"
while true; do
	memuse_fraction=$(get_memuse)
	if [[ $(bc <<< "${memuse_fraction} > ${args[cutoff]}") = 1 ]] ; then
		maxuser=$(get_maxuser)
		killsome $maxuser
		echo "[$(date)] ($(hostname)) Killed processes of $maxuser" 1>&2
	fi
	sleep ${args[interval]}
done
