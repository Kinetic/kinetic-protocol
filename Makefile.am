ACLOCAL_AMFLAGS = -I m4

EXTRADIST = LICENSES README.md README.autotools

lib_LTLIBRARIES =
if ENABLE_CPP
# kientic protocol library for cpp clients
lib_LTLIBRARIES += libkinetic.pb.la
libkinetic_pb_la_SOURCES = cpp/kinetic.pb.cc cpp/kinetic.pb.h
libkinetic_pb_la_includedir = $(includedir)/kinetic
libkinetic_pb_la_include_HEADERS = cpp/kinetic.pb.h
libkinetic_pb_la_CFLAGS = -I$(top_srcdir) -Wall -Werror -fPIC
libkinetic_pb_la_LDFLAGS = -Wl -release @PACKAGE_VERSION@ @LDFLAGS@

cpp/kinetic.pb.cc cpp/kinetic.pb.h: $(top_srcdir)/kinetic.proto
	mkdir -p cpp
	@PROTOC@ --cpp_out=cpp --proto_path=$(top_srcdir) $(top_srcdir)/kinetic.proto
endif

if ENABLE_C
# kientic protocol library for c clients
lib_LTLIBRARIES += libkinetic.pb-c.la
libkinetic_pb_c_la_SOURCES = c/kinetic.pb-c.c c/kinetic.pb-c.h
libkinetic_pb_c_la_includedir = $(includedir)/kinetic
libkinetic_pb_c_la_include_HEADERS = c/kinetic.pb-c.h
libkinetic_pb_c_la_CFLAGS = -I$(top_srcdir) -Wall -Werror -fPIC
libkinetic_pb_c_la_LDFLAGS = -Wl -release @PACKAGE_VERSION@ @LDFLAGS@

c/kinetic.pb-c.c c/kinetic.pb-c.h: $(top_srcdir)/kinetic.proto
	mkdir -p c
	@PROTOCC@ --c_out=c --proto_path=$(top_srcdir) $(top_srcdir)/kinetic.proto
endif

if ENABLE_PYTHON
# kinetic protocol  library for python clients
kinetic_pb2dir = @pyexecdir@/kinetic
kinetic_pb2_PYTHON = py/kinetic_pb2.py py/__init__.py

py/kinetic_pb2.py: $(top_srcdir)/kinetic.proto
	mkdir -p py
	@PROTOC@ --python_out=py --proto_path=$(top_srcdir) $(top_srcdir)/kinetic.proto
py/__init__.py: py/kinetic_pb2.py
	touch py/__init__.py
endif

clean-local:
	rm -f c/kinetic.pb-c.* cpp/kinetic.pb.* py/kinetic_pb2.*
distclean-local:
	rm -rf c cpp py
	rm -f aclocal.m4 ar-lib compile config.guess config.sub config.h.in configure depcomp install-sh ltmain.sh Makefile.in missing py-compile
	rm -rf m4 autom4te.cache
