
###
 # @Author: Radon
 # @Date: 2022-06-28 08:47:33
 # @LastEditors: Radon
 # @LastEditTime: 2022-07-10 18:45:56
 # @Description: Hi, say something
### 

# Entry
# 第一个参数是afl, aflgo或myfuzz
# 第二个参数表示重复fuzz多少次

download() {
    git clone https://github.com/libming/libming SRC

    rm -rf libming-3120f1cd
    cp -r SRC libming-3120f1cd
    cd libming-3120f1cd
    git checkout 3120f1cd
}

afl() {
    mkdir obj-afl-2.52
    mkdir obj-afl-2.52/temp

    export AFL=/home/radon/Documents/fuzzing/fuzzers/afl-2.52

    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-afl-2.52/temp
    export CC=$AFL/afl-clang-fast
    export CXX=$AFL/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-changes=$TMP_DIR/changeBBs.txt"

    echo $'outputscript.c:1442' > $TMP_DIR/changeBBs.txt

    ./autogen.sh
    cd obj-afl-2.52
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make

    mkdir in
    wget -P in http://condor.depaul.edu/sjost/hci430/flash-examples/swf/bumble-bee1.swf

    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep afl | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFL/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./util/swftophp @@" &
        $AFL/afl-fuzz -M main -m none -k 120 -i in -o out$i ./util/swftophp @@
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

    # Get change lines
    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    # cat $TMP_DIR/commit.diff | /home/radon/Documents/showlinenum/showlinenum.awk show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/BBtargets.txt
    echo $'outputscript.c:1442' > $TMP_DIR/BBtargets.txt

    ./autogen.sh
    cd obj-aflgo
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    echo $'outputscript.c:1442' > $TMP_DIR/changeBBs.txt

    cd util
    $AFLGO/scripts/genDistance.sh $SUBJECT $TMP_DIR swftophp

    cd -
    export ADDITIONAL="-distance=$TMP_DIR/distance.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make

    mkdir in
    wget -P in http://condor.depaul.edu/sjost/hci430/flash-examples/swf/bumble-bee1.swf

    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep aflgo | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFLGO/afl-fuzz -S secondary -z exp -c 45m -m none -k 120 -i in -o out$i ./util/swftophp @@" &
        $AFLGO/afl-fuzz -M main -z exp -c 45m -m none -k 120 -i in -o out$i ./util/swftophp @@
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
    export ADDITIONAL="-fno-discard-value-names -outdir=$TMP_DIR -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps"

    # Get change lines
    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    cat $TMP_DIR/commit.diff | /home/radon/Documents/showlinenum/showlinenum.awk show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/tSrcs.txt

    ./autogen.sh
    cd obj-myfuzz-2.52
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    python $MYFUZZ/scripts/pyscripts/getChangeBBs.py $TMP_DIR

    # Format json
    for jsonf in $(ls $TMP_DIR | grep .json); do
        cat $TMP_DIR/${jsonf} | jq --tab . >$TMP_DIR/temp.json
        mv $TMP_DIR/temp.json $TMP_DIR/${jsonf}
    done

    # Merge json
    cd $TMP_DIR
    cat $(ls | grep "bbFunc[0-9]") | jq -s add --tab >bbFunc.json
    cat $(ls | grep "bbLine[0-9]") | jq -s add --tab >bbLine.json
    cat $(ls | grep "duVar[0-9]") | jq -s add --tab >duVar.json
    cat $(ls | grep "funcEntry[0-9]") | jq -s add --tab >funcEntry.json
    cat $(ls | grep "linebb[0-9]") | jq -s add --tab >linebb.json
    cat $(ls | grep "funcParam[0-9]") | jq -s add --tab >funcParam.json
    cat $(ls | grep "callArgs[0-9]") | jq -s add --tab >callArgs.json
    cat $(ls | grep "maxLine[0-9]") | jq -s add --tab >maxLine.json

    # Delete
    rm $(ls | grep "[0-9].json")
    cd ..

    # Calculate fitness

    python $MYFUZZ/scripts/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt

    export ADDITIONAL="-mydist=$TMP_DIR/mydist.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make

    mkdir in
    wget -P in http://condor.depaul.edu/sjost/hci430/flash-examples/swf/bumble-bee1.swf

    # Run [x] times ...
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep myfuzz | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$MYFUZZ/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./util/swftophp @@" &
        $MYFUZZ/afl-fuzz -M main -m none -k 120 -i in -o out$i ./util/swftophp @@
    done
}

download

if ! [[ "$2" =~ ^[0-9]+$ ]]; then
    echo "$2 is not a number."
    exit
fi

if [ "$1" == "afl" ]; then
    afl $2
elif [ "$1" == "aflgo" ]; then
    aflgo $2
elif [ "$1" == "myfuzz" ]; then
    myfuzz $2
else
    echo "Unknown fuzzer: $1."
    echo "Supported fuzzres: afl, aflgo, myfuzz"
fi