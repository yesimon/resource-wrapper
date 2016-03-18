#!/bin/bash
read -d '' usage <<- EOF
Wrap any program by calling this first. Designed to handle setting program
options for number of cpus/threads by checking the cluster environment
variables first.

Usage:
  resource_wrapper.sh -n <thread_arg> -- <program> [normal_args]

Options:
  -n --nslots <thread_arg> Name of the argument to replace number of cpu slots.
  -j --java-heap If specified, add the appropriate -Xmx flag at the beginning
    of args.

Example:
  resource_wrapper.sh -n --threads -- kraken --db kraken_db input.fastq
EOF

source resource_wrapper_lib.sh

TEMP=$(getopt -o hvjn:m: --long verbose,java-heap,nslots:,memory: \
             -n 'resource_wrapper' -- "$@")

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true; do
    case "$1" in
        -v | --verbose ) VERBOSE=true; shift ;;
        -j | --java-heap ) JAVA_HEAP=true; shift ;;
        -n | --nslots ) NSLOTS_OPT="$2"; shift 2 ;;
        -m | --memory ) MEMORY_OPT="$2"; shift 2 ;;
        -h | --help ) HELP=true; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

PROG="$1"
shift

if [[ "$HELP" == "true" ]]; then
    echo >&2 "$usage"
    exit 1
fi

if [[ -z "$PROG" ]]; then
    echo >&2 "No program specified to run."
    echo >&2 "$usage"
    exit 1
fi


ARGS="$@"
if [[ $JAVA_HEAP == true ]]; then
    jvm_heap_memory_opt ARGS "$ARGS"
fi

if [[ ! -z $NSLOTS_OPT ]]; then
    nslots_replace_opt ARGS --opt "$NSLOTS_OPT" -- $ARGS
fi

exec "$PROG" $ARGS
