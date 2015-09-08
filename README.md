# Resource wrapper

This is a small set of bash scripts to help provide the correct program options
to an underlying program whether run from the command line or in a cluster
execution environment.

Many command line programs provide an option to set the number of threads or
number of cpus, with an option such as -t 6, or --threads 2, with the number
being the number of threads you want to use in the program. However, when
submitting jobs to a cluster scheduler such as LSF, you would typically run
something like

```
# Running locally
bowtie2 -p 4 -x index -U reads.fastq

# Submitted to cluster
bsub -n 4 -R "span[hosts=1]" bowtie2 -p 4 -x index -U reads.fastq
```

This results in the repetitive specification of `-n 4` and `-p 4`. This is error
prone because the user has to remember to change both the bsub invocation as
well as the program invocation match the right number of threads with the
cluster resource reservation. Although some programs may be able to figure out
the number of threads from inspecting the output of `nproc` or perhaps
`multiprocessing.cpu_count()` in python, these report the total number of cpus
on the host, such as 8 or 16, even if you are only allocating 4 slots from the
scheduler.

To this end, the resource wrapper lib provides both a wrapper script, as well as
a library which can be sourced to build more complex wrappers.

## Wrapper script

The wrapper script can be called with arguments to perform pre-canned options,
such as replacing some option with the correct number of cpu slots, or
specifying the max java heap size.

Continuing from the above example, the new usages would be:
```
# Running locally
resource_wrapper.sh -n -p -- bowtie2 -p 4 -x index -U reads.fastq

# Submitted to cluster
bsub -n 4 -R "span[hosts=1]" resource_wrapper.sh -n -p -- bowtie2 -x index -U reads.fastq
```

The -n option for resource wrapper specifies the the option name (-p) that we
want to replace with the correct number of cpu slots. In this case, we don't
need to respecify the number of threads in the command line, since the
resource_wrapper script parses the options list and replaces the -p argument, or
in this case, implicitly adds it to the beginning of the argument list with the
correct number of threads for the job.

## Resource wrapper library

For more advanced operations, it's typically useful to write a shim script. Some
shim scripts are available in the `shims/` folder. So program such as `bwa` you
might write a `bwa.shim` script and place it in your path. Suffixing with
`.shim` makes it easier to use both the original and the shim (for debugging
purposes), and also ensures you don't have to worry about path precedence issues
if you have dotkits or modules changing your path. It also makes it eaiser to
set your editor mode to shell script syntax for that suffix.

Shim scripts will build off functions in the resource_wrapper_lib.sh library,
and a simple example shim script is:

```
#!/bin/bash
source "path/to/resource_wrapper_lib.sh"

nslots_replace_opt ARGS --opt -p -- "$@"
exec bowtie2 $ARGS
```

This is pretty much equivalent to the above wrapper script example, but you can
basically call `bowtie2.shim` just like you would `bowtie2` so it can be a drop
in replacement for your current pipeline and regular usage.
