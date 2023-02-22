###
# @Author: Radon
# @Date: 2023-02-03 14:45:54
# @LastEditors: Radon
# @LastEditTime: 2023-02-22 15:13:41
# @Description: Hi, say something
###

#!/bin/bash

read -p "Do you want to patch CVE-2016-4487? y/n: " res
git clone git://sourceware.org/git/binutils-gdb.git SRC
rm -rf ASAN
cp -r SRC ASAN
cd ASAN
git checkout 2c49145

export CC=clang
export CXX=clang++
export LDFLAGS=-lpthread
export ASAN_OPTIONS="detect_leaks=0 abort_on_error=1 symbolize=0"

# Patch CVE-2016-4487
res="y"
if [ "$res" == "y" ]; then
    cd ..
    cp -r patches/2016-4487/* ASAN/
    cd ASAN
    touch 0.patch.radon.txt
fi

mkdir obj-asan && cd obj-asan
CFLAGS="-fsanitize=address -U_FORTIFY_SOURCE -DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
make clean all

# for f in `ls | grep id`; do echo -e "\n${f}" | cut -d ',' -f 1-3 >> 0.txt; cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/ASAN/obj-asan/binutils/cxxfilt 2>&1 | egrep 'SUMMARY|#[0-9] ' | tee -a 0.txt; done

# CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
