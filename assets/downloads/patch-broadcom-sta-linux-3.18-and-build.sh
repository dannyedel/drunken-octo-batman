#!/bin/bash
set -v
set -e
dget -x http://ftp.de.debian.org/debian/pool/non-free/b/broadcom-sta/broadcom-sta_6.30.223.248-3.dsc
wget -O kernel_3.18.support.diff 'https://bugs.debian.org/cgi-bin/bugreport.cgi?msg=5;filename=kernel_3.18.support.diff;att=1;bug=773713'
wget -O linux-3.18-null-pointer-crash.patch 'https://bugs.debian.org/cgi-bin/bugreport.cgi?msg=15;filename=linux-3.18-null-pointer-crash.patch;att=1;bug=773713'
cd broadcom-sta-6.30.223.248
patch -p1 -i ../kernel_3.18.support.diff
quilt push -a
quilt new 11-linux-3.18-null-pointer-crash.patch
quilt add amd64/src/wl/sys/wl_linux.c
quilt add i386/src/wl/sys/wl_linux.c
(cd i386 ; patch -p1 -i ../../linux-3.18-null-pointer-crash.patch)
(cd amd64 ; patch -p1 -i ../../linux-3.18-null-pointer-crash.patch)
quilt refresh
debuild -uc -us
cd ..
