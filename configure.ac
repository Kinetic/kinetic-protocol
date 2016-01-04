#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ([2.69])
AC_INIT([kinetic-protocol],
    m4_esyscmd_s(echo $(grep ' *optional string protocolVersion = 1 .default =' kinetic.proto | sed 's/.* = \"//;s/\".*//')),
    [info@openkinetic.org])

AC_CONFIG_SRCDIR([kinetic.proto])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([-Wall -Werror foreign subdir-objects])
AC_CONFIG_MACRO_DIR([m4])

# Checks for programs.
AC_PROG_CC
AM_PROG_CC_C_O
AC_PROG_CXX
if x$ac_cv_prog_ac_ct_CXX = x ; then
	AC_MSG_ERROR(no C++ compiler found)
fi
m4_ifdef([AM_PROG_AR], [AM_PROG_AR])
AC_PROG_INSTALL
AM_PROG_LIBTOOL

AC_ARG_ENABLE(python,
        [AS_HELP_STRING([--enable-python[[=yes/no]]],[enable building for python [default=no]])],
        enable_python=$enableval, enable_python=no)
if test "$enable_python" = "yes"; then
        AM_PATH_PYTHON
fi
AM_CONDITIONAL([ENABLE_PYTHON], [test x$enable_python = xyes])

AC_ARG_ENABLE(cpp,
        [AS_HELP_STRING([--enable-cpp[[=yes/no]]],[enable building library for C++ [default=yes]])],
        enable_cpp=$enableval, enable_cpp=yes)
AM_CONDITIONAL([ENABLE_CPP], [test x$enable_cpp = xyes])

AC_ARG_ENABLE(c,
        [AS_HELP_STRING([--enable-c[[=yes/no]]],[enable building library for C [default=yes]])],
        enable_c=$enableval, enable_c=yes)
AM_CONDITIONAL([ENABLE_C], [test x$enable_c = xyes])
if test "$enable_c" = "yes" || test "$enable_cpp" = "yes" || test "$enable_python" = "yes"; then
        AC_PATH_PROG(PROTOC, protoc, not-found)
        AS_IF([test "$PROTOC" = "not-found"], [AC_MSG_ERROR(cannot find protoc)])
        PROTOC_VERSION=`$PROTOC --version | awk '{ print $2}'`
        AC_MSG_CHECKING([is protoc version >= 2.5.0])
        AS_VERSION_COMPARE(${PROTOC_VERSION}, 2.5.0, [RESULT=-1], [RESULT=0], [RESULT=1])
        AS_IF([test "${RESULT}" != "-1"], AC_MSG_RESULT([found protoc $PROTOC_VERSION]),
                AC_MSG_ERROR([found protoc v$PROTOC_VERSION needed v2.5.0 or higher]))
fi
if test "$enable_c" = "yes"; then
        AC_PATH_PROG(PROTOCC, protoc-c, not-found)
        AS_IF([test "$PROTOCC" = "not-found"], [AC_MSG_ERROR(cannot find protoc-c)])
        PROTOBUFC_VERSION=`$PROTOCC --version | head -n1 | awk '{ print $2}'`
        AC_MSG_CHECKING([is protobuf-c version >= 1.0.1])
        AS_VERSION_COMPARE(${PROTOBUFC_VERSION}, 1.0.1, [RESULT=-1], [RESULT=0], [RESULT=1])
        AS_IF([test "${RESULT}" != "-1"], AC_MSG_RESULT([found protoc-c $PROTOBUFC_VERSION]),
                AC_MSG_ERROR([found protobuf-c v$PROTOBUFC_VERSION needed v1.0.1 or higher]))

        AC_CHECK_HEADER([protobuf-c/protobuf-c.h], [],
		[AC_CHECK_HEADER([google/protobuf-c/protobuf-c.h],
			[CPPFLAGS="${CPPFLAGS} -Igoogle"],
			[AC_MSG_ERROR(cannot find protobuf-c headers)])])
fi

if test "$enable_cpp" = "yes"; then
        AC_LANG_PUSH([C++])
        AC_CHECK_HEADER([google/protobuf/stubs/common.h],[],
                AC_MSG_ERROR(cannot find protobuf headers))
        AC_LANG_POP
fi

AC_ARG_ENABLE(java,
        [AS_HELP_STRING([--enable-java[[=yes/no]]],[enable building library for java [default=no]])],
        enable_java=$enableval, enable_java=no)
if test "$enable_java" = "yes"; then
        AC_MSG_ERROR(building java library - feature not supported yet)
fi
AM_CONDITIONAL([ENABLE_JAVA], [test x$enable_java = xyes])

AC_CONFIG_FILES([Makefile])

AC_OUTPUT

AC_MSG_RESULT([
	$PACKAGE-$VERSION
	CC:		${CC}
	CPP:		${CPP}
	CFLAGS:		${CFLAGS}
	CPPFLAGS:	${CPPFLAGS}
	CXX:		${CXX}
	CXXCPP:		${CXXCPP}
	CXXFLAGS:	${CXXFLAGS}
	LDFLAGS:	${LDFLAGS}
	LIBS:		${LIBS}

	prefix:		${prefix}
	exec_prefix:	${exec_prefix}
	libdir:		${libdir}
	includedir:	${includedir}
	bindir:		${bindir}
])
if test "$enable_python" = "yes"; then
AC_MSG_RESULT([
	PYTHON:		${PYTHON}
	pyexecdir:	${pyexecdir}
	pythondir	${pythondir}
])
fi
