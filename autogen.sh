#!/bin/sh
libtoolize
aclocal -I m4
autoheader
autoconf
automake --add-missing

# If there are any options, assume the user wants to run configure.
# To run configure w/o any options, use ./autogen.sh --configure
if [ $# -gt 0 ] ; then
        case "$1" in
        --conf*)
                shift 1
                ;;
        esac
    exec ./configure  "$@"
fi
