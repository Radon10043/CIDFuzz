###
# @Author: Radon
# @Date: 2023-01-25 17:02:53
# @LastEditors: Radon
# @LastEditTime: 2023-01-27 15:38:38
# @Description: Hi, say something
###

download() {
    git clone git://sourceware.org/git/binutils-gdb.git SRC
    rm -rf binutils-2c49145
    cp -r SRC binutils-2c49145
    cd binutils-2c49145
    git checkout 2c49145
}

afl() {
    export AFL=/home/radon/Documents/fuzzing/fuzzers/afl-2.52
    export CC=$AFL/afl-clang-fast
    export CXX=$AFL/afl-clang-fast++
    export LDFLAGS=-lpthread
    export AFL_NO_UI=1

    mkdir obj-afl && cd obj-afl
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all

    mkdir in
    echo "" >in/in
    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        $AFL/afl-fuzz -S secondary -i in -o out$i -m none -k 480 binutils/cxxfilt &
        $AFL/afl-fuzz -M main -i in -o out$i -m none -k 480 binutils/cxxfilt &
    done
}

aflgo() {
    echo "AFLGo!"
}

myfuzz() {
    echo "myfuzz!"
}

# Entry
# 第一个参数是表示用哪个工具进行测试
# 第二个参数是数字, 表示重复fuzz多少次

download

if ! [[ "$2" =~ ^[0-9]+$ ]]; then
    echo "$2 is not a number."
    exit
fi

echo "$2 is a number, yeah!"

export SHOWLINENUM=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b/scripts/showlinenum.awk
if [ "$1" == "afl" ]; then
    afl $2
elif [ "$1" == "aflgo" ]; then
    aflgo $2
elif [ "$1" == "myfuzz" ]; then
    myfuzz $2
else
    echo "Unknown fuzzer: $1"
    echo "Supported fuzzers: afl, aflgo, myfuzz"
fi
