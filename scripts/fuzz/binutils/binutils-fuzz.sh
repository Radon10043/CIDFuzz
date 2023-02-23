###
# @Author: Radon
# @Date: 2023-01-25 17:02:53
# @LastEditors: Radon
# @LastEditTime: 2023-02-22 16:59:19
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

    mkdir obj-afl && cd obj-afl
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all

    mkdir in
    echo "" >in/in
    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        timeout 8h $AFL/afl-fuzz -d -i in -o out$i -m none binutils/cxxfilt &
    done
}

aflgo() {
    export AFLGO=/home/radon/Documents/fuzzing/fuzzers/aflgo
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-aflgo/temp
    export CC=$AFLGO/afl-clang-fast
    export CXX=$AFLGO/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-targets=$TMP_DIR/BBtargets.txt -outdir=$TMP_DIR -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps"
    mkdir obj-aflgo && mkdir obj-aflgo/temp

    # Set targets
    if [ "$2" == "CVE-2016-4487" ]; then # CVE-2016-4487
        echo $'cxxfilt.c:227\ncxxfilt.c:62\ncplus-dem.c:886\ncplus-dem.c:1203\ncplus-dem.c:1490\ncplus-dem.c:2594\ncplus-dem.c:4319' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-4488" ]; then # CVE-2016-4488
        echo $'cplus-dem.c:1203\ncplus-dem.c:1490\ncplus-dem.c:2617\ncplus-dem.c:4292\ncplus-dem.c:886\ncxxfilt.c:227\ncxxfilt.c:62' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-4489" ]; then # CVE-2016-4489
        echo $'cplus-dem.c:1190\ncplus-dem.c:3007\ncplus-dem.c:4839\ncplus-dem.c:886\ncxxfilt.c:172\ncxxfilt.c:227\ncxxfilt.c:62' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-4490" ]; then # CVE-2016-4490
        echo $'cxxfilt.c:227\ncxxfilt.c:62\ncplus-dem.c:864\ncp-demangle.c:6102\ncp-demangle.c:5945\ncp-demangle.c:5894\ncp-demangle.c:1172\ncp-demangle.c:1257\ncp-demangle.c:1399\ncp-demangle.c:1596' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-4491" ]; then # CVE-2016-4491
        echo $'cp-demangle.c:4320\ncp-demangle.c:4358\ncp-demangle.c:4929\ncp-demangle.c:4945\ncp-demangle.c:4950\ncp-demangle.c:5394\ncp-demangle.c:5472\ncp-demangle.c:5536\ncp-demangle.c:5540\ncp-demangle.c:5592\ncp-demangle.c:5731' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-4492" ]; then # CVE-2016-4492
        echo $'cplus-dem.c:1203\ncplus-dem.c:1562\ncplus-dem.c:1642\ncplus-dem.c:2169\ncplus-dem.c:2229\ncplus-dem.c:3606\ncplus-dem.c:3671\ncplus-dem.c:3781\ncplus-dem.c:4231\ncplus-dem.c:4514\ncplus-dem.c:886\ncxxfilt.c:227\ncxxfilt.c:62' >$TMP_DIR/BBtargets.txt
    elif [ "$2" == "CVE-2016-6131" ]; then # CVE-2016-6131
        echo $'cxxfilt.c:227\ncxxfilt.c:62\ncplus-dem.c:886\ncplus-dem.c:1203\ncplus-dem.c:1665\ncplus-dem.c:4498\ncplus-dem.c:4231\ncplus-dem.c:3811\ncplus-dem.c:4018\ncplus-dem.c:2543\ncplus-dem.c:2489' >$TMP_DIR/BBtargets.txt
    else
        echo "Unsupported target! Supported target:"
        echo "CVE-2016-4487, CVE-2016-4488, CVE-2016-4489, CVE-2016-4490"
        echo "CVE-2016-4491, CVE-2016-4492, CVE-2016-6131"
        exit 1
    fi

    cd obj-aflgo
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error $ADDITIONAL" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all
    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt
    cd binutils
    $AFLGO/scripts/genDistance.sh $SUBJECT $TMP_DIR cxxfilt

    cd ../../
    mkdir obj-dist
    cd obj-dist # work around because cannot run make distclean
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error -distance=$TMP_DIR/distance.cfg.txt" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all

    mkdir in
    echo "" >in/in
    for ((i = 1; i <= $1; i++)); do
        timeout 8h $AFLGO/afl-fuzz -d -m none -z exp -c 7h -i in -o out$i binutils/cxxfilt &
    done
}

myfuzz() {
    export CIDFUZZ=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-myfuzz-2.52/temp
    export CC=$CIDFUZZ/afl-clang-fast
    export CXX=$CIDFUZZ/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-fno-discard-value-names -outdir=$TMP_DIR -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps"
    mkdir obj-myfuzz-2.52
    mkdir obj-myfuzz-2.52/temp

    # Set targets
    if [ "$2" == "CVE-2016-4487" ]; then # CVE-2016-4487
        echo $'cplus-dem.c:4319' >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-4488" ]; then # CVE-2016-4488
        echo "cplus-dem.c:4292" >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-4489" ]; then # CVE-2016-4489
        echo $'cplus-dem.c:4839' >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-4490" ]; then # CVE-2016-4490
        echo $'cp-demangle.c:1596' >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-4491" ]; then # CVE-2016-4491
        echo $'cp-demangle.c:5394' >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-4492" ]; then # CVE-2016-4492
        echo $'cplus-dem.c:3606\ncplus-dem.c:3781\ncplus-dem.c:2169' >$TMP_DIR/tSrcs.txt
    elif [ "$2" == "CVE-2016-6131" ]; then # CVE-2016-6131
        echo $'cplus-dem.c:3811\ncplus-dem.c:4018\ncplus-dem.c:2543\ncplus-dem.c:2489' >$TMP_DIR/tSrcs.txt
    else
        echo "Unsupported target! Supported target:"
        echo "CVE-2016-4487, CVE-2016-4488, CVE-2016-4489, CVE-2016-4490"
        echo "CVE-2016-4491, CVE-2016-4492, CVE-2016-6131"
        exit 1
    fi

    cd obj-myfuzz-2.52
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error $ADDITIONAL" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    # Format json
    echo "Formatting json files ..."
    for jsonf in $(ls $TMP_DIR | grep .json); do
        cat $TMP_DIR/${jsonf} | jq --tab . >$TMP_DIR/temp.json
        mv $TMP_DIR/temp.json $TMP_DIR/${jsonf}
    done

    # Merge json
    echo "Merging json files ..."
    cd $TMP_DIR
    names=(bbFunc bbLine duVar funcEntry linebb funcParam callArgs maxLine)
    for name in ${names[@]}; do
        cat $(ls | grep $name"[0-9]") | jq -s add --tab >$name.json
    done

    # Delete
    echo "Deleting redudant files ..."
    rm $(ls | grep "[0-9].json")
    cd ..

    # Calculate fitness
    python $CIDFUZZ/scripts/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt

    cd ../
    mkdir obj-cidist && cd obj-cidist
    CFLAGS="-DFORTIFY_SOURCE=2 -fstack-protector-all -fno-omit-frame-pointer -g -Wno-error -cidist=$TMP_DIR/cidist.cfg.txt" LDFLAGS="-ldl -lutil" ../configure --disable-shared --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-ld
    make clean all

    mkdir in
    echo "" >in/in

    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        timeout 8h $CIDFUZZ/afl-fuzz -d -m none -i in -o out$i binutils/cxxfilt &
    done
}

# Entry
# 第一个参数是表示用哪个工具进行测试
# 第二个参数是数字, 表示重复fuzz多少次
# 第三个参数是编号, 表示对哪个漏洞进行定向测试, e.g. CVE-2016-4487

export SHOWLINENUM=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b/scripts/showlinenum.awk
export AFL_NO_UI=1
export AFL_USE_ASAN=1
export ASAN_OPTIONS="detect_leaks=0 abort_on_error=1 symbolize=0"

if ! [[ "$2" =~ ^[0-9]+$ ]]; then
    echo "$2 is not a number."
    exit
fi
echo "$2 is a number, yeah!"

download

if [ "$1" == "afl" ]; then
    afl $2
elif [ "$1" == "aflgo" ]; then
    aflgo $2 $3
elif [ "$1" == "myfuzz" ]; then
    myfuzz $2 $3
else
    echo "Unknown fuzzer: $1"
    echo "Supported fuzzers: afl, aflgo, myfuzz"
fi
