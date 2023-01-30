###
# @Author: Radon
# @Date: 2023-01-27 14:20:09
 # @LastEditors: Radon
 # @LastEditTime: 2023-01-30 13:59:07
# @Description: Hi, say something
###
git clone git://sourceware.org/git/binutils-gdb.git SRC
rm -rf ASAN
cp -r SRC ASAN
cd ASAN
git checkout 2c49145

export CC=clang
export CXX=clang++
export LDFLAGS=-lpthread
export ASAN_OPTIONS="detect_leaks=0"

mkdir obj-asan && cd obj-asan
CFLAGS="-fsanitize=address -DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
make clean all

# for f in `ls | grep id`; do echo -e "\n${f}" | cut -d ',' -f 1-3 >> 0.txt | cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/ASAN/obj-asan/binutils/cxxfilt 2>&1 | grep '#[0-2] ' | tee -a 0.txt; done
