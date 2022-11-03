###
# @Author: Radon
# @Date: 2022-06-28 10:25:33
 # @LastEditors: Radon
 # @LastEditTime: 2022-11-03 22:20:21
# @Description: Hi, say something
###

download() {
    git clone https://github.com/ckolivas/lrzip SRC

    rm -rf lrzip-30f5be91
    cp -r SRC lrzip-30f5be91
    cd lrzip-30f5be91
    git checkout 30f5be91
}

afl() {
    mkdir obj-afl
    mkdir obj-afl/temp

    export AFL=/home/radon/Documents/fuzzing/fuzzers/afl-2.52
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-afl/temp
    export CC=$AFL/afl-clang-fast
    export CXX=$AFL/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-changes=$TMP_DIR/changeBBs.txt"

    echo $'runzip.c:194\nrunzip.c:215\nrunzip.c:217\nrunzip.c:219\nrunzip.c:223\nrunzip.c:224\nrunzip.c:225\nrunzip.c:226\nrunzip.c:233\nrunzip.c:239\nrunzip.c:241' > $TMP_DIR/changeBBs.txt

    ./autogen.sh
    make distclean

    cd obj-afl

    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --prefix=`pwd`
    make clean all
    mkdir in
    cp $AFL/testcases/archives/exotic/lzip/small_archive.lz in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep afl | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFL/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./lrzip -t @@"
        $AFL/afl-fuzz -M main -m none  -k 120 -i in -o out$i ./lrzip -t @@
    done
}

aflgo() {
    mkdir obj-aflgo
    mkdir obj-aflgo/temp

    export AFLGO=/home/radon/Documents/fuzzing/fuzzers/aflgo
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-aflgo/temp
    export CC=$AFLGO/afl-clang-fast
    export CXX=$AFLGO/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-targets=$TMP_DIR/BBtargets.txt -outdir=$TMP_DIR -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps"

    ./autogen.sh
    make distclean

    cd obj-aflgo

    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    # cat $TMP_DIR/commit.diff | $SHOWLINENUM show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/BBtargets.txt
    echo $'runzip.c:194\nrunzip.c:215\nrunzip.c:217\nrunzip.c:219\nrunzip.c:223\nrunzip.c:224\nrunzip.c:225\nrunzip.c:226\nrunzip.c:233\nrunzip.c:239\nrunzip.c:241' > $TMP_DIR/BBtargets.txt

    echo $'runzip.c:194\nrunzip.c:215\nrunzip.c:217\nrunzip.c:219\nrunzip.c:223\nrunzip.c:224\nrunzip.c:225\nrunzip.c:226\nrunzip.c:233\nrunzip.c:239\nrunzip.c:241' > $TMP_DIR/changeBBs.txt

    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --prefix=`pwd`
    make clean all

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    # Can't calculate distance?
    echo "" > $TMP_DIR/distance.cfg.txt
    $AFLGO/scripts/genDistance.sh $SUBJECT $TMP_DIR lrzip

    export ADDITIONAL="-distance=$TMP_DIR/distance.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --prefix=`pwd`
    make clean all

    mkdir in
    cp $AFLGO/testcases/archives/exotic/lzip/small_archive.lz in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep aflgo | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFLGO/afl-fuzz -S secondary -m none -k 120 -z exp -c 45m -i in -o out$i ./lrzip -t @@"
        $AFLGO/afl-fuzz -M main -m none -k 120 -z exp -c 45m -i in -o out$i ./lrzip -t @@
    done
}

myfuzz() {
    mkdir obj-myfuzz-2.52
    mkdir obj-myfuzz-2.52/temp

    export MYFUZZ=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-myfuzz-2.52/temp
    export CC=$MYFUZZ/afl-clang-fast
    export CXX=$MYFUZZ/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-outdir=$TMP_DIR -fno-discard-value-names"

    ./autogen.sh
    make distclean

    cd obj-myfuzz-2.52

    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --prefix=`pwd`
    make clean all

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    # Format json
    for jsonf in $(ls $TMP_DIR | grep .json); do
        cat $TMP_DIR/${jsonf} | jq --tab . >$TMP_DIR/temp.json
        mv $TMP_DIR/temp.json $TMP_DIR/${jsonf}
    done

    # Merge json
    cd $TMP_DIR
    names=(bbFunc bbLine duVar funcEntry linebb funcParam callArgs maxLine)
    for name in ${names[@]}; do
        cat $(ls | grep $name"[0-9]") | jq -s add --tab >$name.json
    done

    # Delete
    rm $(ls | grep "[0-9].json")
    cd ..

    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    cat $TMP_DIR/commit.diff | $SHOWLINENUM show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/tSrcs.txt

    python $MYFUZZ/scripts/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt

    # python $MYFUZZ/scripts/pyscripts/getChangeBBs.py $TMP_DIR
    echo $'runzip.c:194\nrunzip.c:215\nrunzip.c:217\nrunzip.c:219\nrunzip.c:223\nrunzip.c:224\nrunzip.c:225\nrunzip.c:226\nrunzip.c:233\nrunzip.c:239\nrunzip.c:241' > $TMP_DIR/changeBBs.txt

    export ADDITIONAL="-mydist=$TMP_DIR/mydist.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --prefix=`pwd`
    make clean all

    mkdir in
    cp $MYFUZZ/testcases/archives/exotic/lzip/small_archive.lz in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep myfuzz | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$MYFUZZ/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./lrzip -t @@"
        $MYFUZZ/afl-fuzz -M main -m none  -k 120 -i in -o out$i ./lrzip -t @@
    done
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
