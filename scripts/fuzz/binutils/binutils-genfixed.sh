###
# @Author: Radon
# @Date: 2023-02-10 17:13:42
# @LastEditors: Radon
# @LastEditTime: 2023-02-11 10:43:16
# @Description: Hi, say something
###
#!/bin/bash

export CC=clang
export CXX=clang++
export LDFLAGS=-lpthread
export ASAN_OPTIONS="detect_leaks=0 abort_on_error=1 symbolize=0"

NUMBERS=(4487 4489 4490 4491 4492 6131)

git clone git://sourceware.org/git/binutils-gdb.git SRC

for NUMBER in ${NUMBERS[@]}; do
    if [ -d "PATCH-2016-"$NUMBER ]; then
        echo "PATCH-2016-"$NUMBER" already exists, skip ..."
        sleep 4s
    else
        echo "Building PATCH-2016-$NUMBER ..."
        cp -r SRC PATCH-2016-$NUMBER
        cd PATCH-2016-$NUMBER
        git checkout 2c49145
        mkdir obj-build && cd obj-build
        CFLAGS="-fsanitize=address -U_FORTIFY_SOURCE -DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld >/dev/null
        make clean all >/dev/null
        cd ../../
    fi
done
