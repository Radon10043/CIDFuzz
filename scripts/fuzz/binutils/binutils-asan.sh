###
# @Author: Radon
# @Date: 2023-01-27 14:20:09
 # @LastEditors: Radon
 # @LastEditTime: 2023-02-06 15:02:25
# @Description: Hi, say something
###
read -p "Do you want to patch CVE-2016-4487? y/n: " res

git clone git://sourceware.org/git/binutils-gdb.git SRC
rm -rf ASAN
cp -r SRC ASAN
cd ASAN
git checkout 2c49145

export CC=clang
export CXX=clang++
export LDFLAGS=-lpthread
export ASAN_OPTIONS="detect_leaks=0"

# Patch CVE-2016-4487
if [ "$res" == "y" ]; then
    cp ../patches/patch-2016-4487-cplus-dem.c ./libiberty/cplus-dem.c
fi

mkdir obj-asan && cd obj-asan
CFLAGS="-fsanitize=address -DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
make clean all

# for f in `ls | grep id`; do echo -e "\n${f}" | cut -d ',' -f 1-3 >> 0.txt | cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/ASAN/obj-asan/binutils/cxxfilt 2>&1 | egrep 'SUMMARY|#[0-9] ' | tee -a 0.txt; done

# CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld