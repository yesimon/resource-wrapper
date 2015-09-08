#!/bin/bash
# Provide some functions for writing executable shims to handle cluster
# environment. Bash can't return non-integer values. So for the functions below
# we choose to edit the var name passed in $1 via eval for many of these
# functions. This is instead of running function in subshell and returning via
# echo to avoid spawning a subshell and allowing echo within the shell not
# messing up the return value.

# Calculates the number of cpus provided by cluster. Normally programs use
# `nproc`, or /proc/cpuinfo to determine the number of cpus on the machine. This
# is inappropriate in a cluster environment because you may be allocated 2 slots
# out of 8, but nproc will report 8, the total number of slots on the host
# machine.
# Supports LSF and GridEngine. After specifiying all relevant arguments for this
# function, add -- and your normal arguments.
# Example:
#    ncpu_replace_opt ARGS --opt -t -- --db dbfile -t 3
#
# Usage:
#   --sep -t (Name of the option you want to replace/insert, like '-t', or '--ncpus').
#   --location before (Either 'before' or 'after'. Whether to prepend the fixed
#                      option before or after the args string.)
#   --sep ' ' (Separator between the argument and value, typically either "=" or
#              " " like -t=6 or -t 6. Defaults to ' ')
#   --nproc (If specified, forcibly run nproc and use that value. Useful for
#            programs that always default to 1 thread.)
nslots_replace_opt() {
    local __outvar="$1"
    shift 1
    local location="before"
    local sep=" "
    local nproc
    while true; do
        case "$1" in
            --opt ) local opt="$2"; shift 2;;
            --location ) location="$2"; shift 2;;
            --sep ) sep="$2"; shift 2;;
            --nproc ) nproc="true"; shift ;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
    # Suffix local var to avoid potential shadowing in eval
    local args__ncpu_replace_opt
    if [[ "$nproc" == "true" ]]; then
        determine_nslots "nproc"
        local nslots=$?
    else
        determine_nslots
        local nslots=$?
    fi
    if [[ "$nslots" -gt 0 ]]; then
        regex_replace_opt args__ncpu_replace_opt --opt "$opt" --value "$nslots" \
                          --location "$location" --sep "$sep" -- "$@"
        eval $__outvar=\$args__ncpu_replace_opt
    else
        # Not running in cluster context or forced nproc. Don't do replacements.
        eval $__outvar=\$@
    fi
}

# Determine number of slots if in cluster context.
# If the first argument is nproc, actually use nproc command to get current
# number of cpu cores, otherwise just return 0 for "no info".
determine_nslots() {
    if [[ -n "$LSB_DJOB_NUMPROC" ]]; then
        return $LSB_DJOB_NUMPROC
    elif [[ -n "$NSLOTS" ]]; then
        return $NSLOTS
    elif [[ "$1" == "nproc" ]]; then
        return $(nproc)
    else
        return 0
    fi
}

# Replace the specified option in the args string with the specified value using
# a regex. Place your input argument string after --.
# Example:
#   regex_replace_opt REPLACED --opt -t --value 6 --sep '=' \
#     --location=before -- -db dbfile -t 3
#
#   After running, $REPLACED will be:
#     -t=6 --db dbfile
# Usage:
#   --opt -t (Name of the option you want to replace/insert, like '-t', or '--ncpus').
#   --value 6 (Value to replace for the option.)
#   --location before (Either 'before' or 'after'. Whether to prepend the fixed
#                      option before or after the args string.)
#   --sep ' ' (Separator between the argument and value, typically either "=" or
#              " " like -t=6 or -t 6. Defaults to ' ')
#   --nproc (If specified, forcibly run nproc and use that value. Useful for
#            programs that always default to 1 thread.)
regex_replace_opt() {
    local __outvar="$1"
    shift 1
    local location="before"
    local sep=" "
    while true; do
        case "$1" in
            --opt ) local opt="$2"; shift 2;;
            --value ) local value="$2"; shift 2;;
            --sep ) sep="$2"; shift 2;;
            --location ) location="$2"; shift 2;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
    # Suffix local var to avoid potential shadowing in eval
    if [[ "$@" =~ (.*)[[:space:]]*$opt$sep([^[:space:]]+)(.*) ]]; then
        local prepped_args="${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"
    else
        # Option was not found, return simple prepend of desired option.
        local prepped_args="$@"
    fi
    if [[ $location == "before" ]]; then
        local args__regex_replace_opt="$opt$sep$value $prepped_args"
    elif [[ $location == "after" ]]; then
        local args__regex_replace_opt="$prepped_args $opt$sep$value"
    fi
    eval $__outvar=\$args__regex_replace_opt
}

# Determine the memory limit for the current job. Requires LSF > 9.1.
lsf_memory_limit() {
    # LSF reports memory in MB. Requests memory in GiB.
    local __outvar="$1"
    # This depends on the cluster configuration, but LSF seems to set the
    # default into RSRCREQ. So should never reach other branch.
    local lsf_default_mem=750
    if [[ "$LSB_EFFECTIVE_RSRCREQ" =~ .*rusage\[mem=([0-9]+\.?[0-9]*)\].* ]]; then
        local mem_MB="${BASH_REMATCH[1]}"
        # Convert from MB to MiB.
        local mem_lsf_memory_limit=$(bc <<< "scale=0; $mem_MB * 0.953674")
    else
        local mem_lsf_memory_limit="$lsf_default_mem"
    fi
    local mem_lsf_memory_limit=$(printf "%.*f\n" 1 $mem_lsf_memory_limit)
    eval $__outvar=\$mem_lsf_memory_limit
}

determine_memory_limit() {
    local __outvar="$1"
    shift 1
    local mem__determine_memory_limit
    if [[ -n "$LSB_JOBID" ]]; then
        lsf_memory_limit mem__determine_memory_limit
        eval $__outvar=\$mem__determine_memory_limit
    else
        eval $__outvar=0
    fi
}

# Precanned option to place a -Xmx###m string at the beginning of your args.
# Simply measures the amount of memory allocated by LSF and set the value.
# Otherwise, don't add anything. This may change to allow options to
# add/multiple against the LSF memory limit because there is some wiggle room in
# exceeding the limits.
jvm_heap_memory_opt() {
    local __outvar="$1"
    shift 1
    # Suffix local var to avoid potential shadowing in eval
    local args__jvm_heap_memory_opt
    local mem_MiB
    determine_memory_limit mem_MiB
    if [[ mem_MiB -gt 0 ]]; then
        regex_replace_opt args__jvm_heap_memory_opt --opt "-Xmx" \
                          --value "${mem_MiB}m" --sep '' -- "$@"
    else
        # Not running in cluster context. Don't do replacements.
        args__jvm_heap_memory_opt="$@"
    fi
    eval $__outvar=\$args__jvm_heap_memory_opt
}
