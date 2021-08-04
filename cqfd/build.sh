#!/bin/bash
#
# Yocto build system initiator.
#
# Copyright (C) 2019-2021 Savoir-faire Linux, Inc.
# This program is distributed under the Apache 2 license.
# Name:       print_usage
# Brief:      Print script usage
print_usage()
{
    echo "This script builds a yocto distribution
./$(basename ${0}) [OPTIONS]
Options:
        (-d|--dl-dir)           <path>                  Yocto downloads cache directory
        (-i|--image)            <image>                 Yocto target image
        (--distro)              <distro>                Yocto target distribution
        (-m|--machine)          <machine>               Yocto target machine
        (-s|--sstate-dir)       <path>                  Yocto build cache directory
        (-k|--sdk)                                      Compile the SDK
        (-r|--remove-build-dir)                         Remove Yocto build directory
        (-v|--verbose)                                  Verbose mode
        (--debug)                                       Print all commands
        (--no-layers-update)                            Don't auto update bblayers.conf
        (-h|--help)                                     Display this help message
        (--)                    <command>               Command to launch
        "
}
# Name:       apply_patch
# Brief:      Test and apply a patch file if needed
# Param[in]:  Patch file
apply_patch()
{
    print_noln "  Test patch ${1}"
    if [[ ! -f ${1}.done ]]; then
        patch --dry-run --silent --strip=1 --force --input "${1}"
        ret=$?
        if [[ $ret -ne 0 ]]; then
            check_result "$ret" "    Error testing patch ${1}"
        else
            print_out
            print_noln "  Apply patch ${1}"
            patch --strip=1 --force --input "${1}"
            ret=$?
            check_result "$ret" "    Error applying patch ${1}"
            touch "${1}.done"
            print_ok
        fi
    else
            print_out
            print_noln "    Patch ${1} has already been applied -- skipping"
            print_warn
    fi
}
# Name:       parse_options
# Brief:      Parse options from command line
# Param[in]:  Command line parameters
parse_options()
{
    ARGS=$(getopt -o "d:i:khm:rs:v" -l "distro:,dl-dir:,help,image:,machine:,no-layers-update,debug,remove-build-dir,sdk,sstate-dir:,verbose" -n "build.sh" -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        exit 1
    fi
    eval set -- "${ARGS}"
    while true; do
        case "$1" in
            --distro)
                export DISTRO=$2
                shift 2
                ;;
            -d|--dl-dir)
                if [ ! -d "$2" ]; then
                    echo "Fatal: specified dl-dir does not exist"
                    exit 1
                fi
                export DL_DIR=$(readlink -f $2)
                export BB_GENERATE_MIRROR_TARBALLS="1"
                shift 2
                ;;
            --debug)
                set -x
                shift
                ;;
            -i|--image)
                export IMAGE=$2
                shift 2
                ;;
            --no-layers-update)
                NO_LAYERS_UPDATE=yes
                shift
                ;;
            -m|--machine)
                export MACHINE=$2
                shift 2
                ;;
            -r|--remove-build-dir)
                REMOVE_BUILDDIR=1
                shift
                ;;
            -k|--sdk)
                COMPILE_SDK=1
                shift
                ;;
            -s|--sstate-dir)
                if [ ! -d "$2" ]; then
                    echo "Fatal: specified state-dir does not exist"
                    exit 1
                fi
                export SSTATE_DIR=$(readlink -f $2)
                shift 2
                ;;
            --meta-list-file)
                export META_LIST_FILE=$(readlink -f $2)
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 1
                shift
                break
                ;;
            -|--)
                shift
                CMD=$@
                break
                ;;
            *)
                print_usage
                exit 1
                shift
                break
                ;;
        esac
    done
}
# Name:       run_cmd
# Brief:      Run given command with enhanced display and return code checked
# Param[in]:  Command description to print
# Param[in]:  The command itself
run_cmd()
{
  # Description to display
  description=$1
  print_noln "$description"
  # Remove description from parameters
  shift
  # Launch command
  eval $@
  # Check command result, exit on error
  check_result $?
  # Print ok otherwise
  print_ok
}
# Name        filter_layers_blocklist
# Brief       Filter out layers listed in layers.blocklist from stdin
filter_layers_blocklist()
{
    local filter
    local layer
    local sep
    # Build $filter, a |-separated list of layers to exclude
    if [ -s "${TOPDIR}/layers.blocklist" ]; then
        while read -r layer; do
            [ -z "$layer" ] && continue
            if [ -d "${SOURCESDIR}/${layer}" ]; then
                filter+="${sep}${SOURCESDIR}/${layer}"
                sep="|" # separator for 2nd and next items
            else
                print_ko_ "layers.blocklist entry not found: ${layer}"
            fi
        done < "${TOPDIR}/layers.blocklist"
        filter="(${filter})"
    fi
    if [ "${filter}" ]; then
        # eg. "^(meta-foobar|meta-foobiz)$"
        grep -Ev "^${filter}$"
    else
        cat
    fi
}
# Name        update_layers
# Brief       Add layers in bblayers.conf using bitbake-layers add-layer,
#             unless NO_LAYERS_UPDATE is set.
update_layers()
{
    local layers_to_add
    [ -n "${NO_LAYERS_UPDATE}" ] && return 0
    layers_to_add=$(find "${SOURCESDIR}"/meta-* \
        "${SOURCESDIR}"/poky/meta-* \
        -type f \
        -path '*/conf/layer.conf' \
        -print0 |
        xargs -0 -n1 dirname |
        xargs -n1 dirname |
        filter_layers_blocklist)
    if [ -n "${layers_to_add}" ]; then
        run_cmd "update layers" "bitbake-layers add-layer ${layers_to_add}"
    fi
}
##########################
########## MAIN ##########
##########################
# Include scripting tools
. scripts/bash_scripting_tools/functions.sh
#### Local vars ####
# Not verbose by default
export VERBOSE=0
# Keep directory to retrieve tools
TOPDIR=$(dirname $(readlink -f ${0}))
BUILDDIR=${TOPDIR}/build
SOURCESDIR=${TOPDIR}/sources
POKYDIR=$(dirname $(find "${SOURCESDIR}" -name "oe-init-build-env" -print -quit))
# Change to top directory
cd "${TOPDIR}"
# Check for Poky directory
if [ -z "${POKYDIR}" ]; then
  print_ko_ "poky directory cannot be found"
  exit 1
fi
# Parse options
parse_options "${@}"
# Display VARIABLES
echo "CMD = '$CMD'"
echo "DL_DIR = '$DL_DIR'"
echo "BB_GENERATE_MIRROR_TARBALLS" = "$BB_GENERATE_MIRROR_TARBALLS"
echo "SSTATE_DIR = '$SSTATE_DIR'"
# Init display
init_output $VERBOSE build
# Apply patches
if [ -d patches ] && [ -f patches/*.patch ]; then
    print_out "Applying patches"
    for patch in patches/*.patch
    do
        apply_patch ${patch}
    done
fi
# Set variable readable from command line
export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE \
  DISTRO \
  DL_DIR \
  BB_GENERATE_MIRROR_TARBALLS \
  MACHINE \
  SSTATE_DIR \
  ACCEPT_FSL_EULA \
"
# Set image to build, default to core-image-minimal
export IMAGE=${IMAGE:-"tdx-reference-minimal-image"}
export MACHINE=${MACHINE:-"apalis-imx6"}
export DISTRO=${DISTRO:-"tdx-x11"}
export ACCEPT_FSL_EULA="1"
if [ ! -z "$REMOVE_BUILDDIR" ]; then
  # Clean directory
  run_cmd "Remove build directory" rm -Rf "${BUILDDIR}"
else
  # Clean layers
  if [ -z "${NO_LAYERS_UPDATE}" ] ; then
    run_cmd "Remove bblayers.conf" rm -f ${BUILDDIR}/conf/bblayers.conf
  fi
fi
# Init poky build
set "${BUILDDIR}"
. "${POKYDIR}"/oe-init-build-env
# Add layers
update_layers
# Build Yocto
if [ ! -z "$CMD" ]; then
  run_cmd "Launch custom command (should take a while)..." "$CMD"
elif [ -z "$COMPILE_SDK" ]; then
  run_cmd "Build image (should take a while)..." bitbake "$IMAGE"
else
  run_cmd "Build sdk (should take a while)..." bitbake "$IMAGE" -c populate_sdk
fi
