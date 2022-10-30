###
# @Author: Radon
# @Date: 2022-06-28 09:55:58
 # @LastEditors: Radon
 # @LastEditTime: 2022-10-30 22:15:30
# @Description: Hi, say something
###

download() {
    git clone https://gitlab.gnome.org/GNOME/libxml2.git SRC

    rm -rf libxml2-96849544
    cp -r SRC libxml2-96849544
    cd libxml2-96849544
    git checkout 96849544
}

afl() {
    mkdir obj-afl
    mkdir obj-afl/temp

    export AFL=/home/radon/Documents/fuzzing/fuzzers/afl-2.52
    export TMP_DIR=$PWD/obj-afl/temp
    export CC=$AFL/afl-clang-fast
    export CXX=$AFL/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-changes=$TMP_DIR/changeBBs.txt"

    echo $'parser.c:7129\nparser.c:7130' >$TMP_DIR/changeBBs.txt

    ./autogen.sh
    make distclean

    cd obj-afl

    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean all

    mkdir in
    cp $AFL/testcases/others/xml/small_document.xml in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep afl | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFL/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./xmllint --valid @@" &
        $AFL/afl-fuzz -M main -m none -k 120 -i in -o out$i ./xmllint --valid @@
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

    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    # cat $TMP_DIR/commit.diff | $SHOWLINENUM show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/BBtargets.txt
    echo $'parser.c:7129\nparser.c:7130' >$TMP_DIR/BBtargets.txt

    echo $'parser.c:7129\nparser.c:7130' >$TMP_DIR/changeBBs.txt

    ./autogen.sh
    make distclean
    cd obj-aflgo
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make -j4

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    $AFLGO/scripts/genDistance.sh $SUBJECT $TMP_DIR xmllint
    CFLAGS="-distance=$TMP_DIR/distance.cfg.txt" CXXFLAGS="-distance=$TMP_DIR/distance.cfg.txt" ../configure --disable-shared --prefix=$(pwd)
    make clean
    make -j4

    mkdir in
    cp $AFLGO/testcases/others/xml/small_document.xml in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep aflgo | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$AFLGO/afl-fuzz -S secondary -z exp -c 45m -m none -k 120 -i in -o out$i ./xmllint --valid @@"
        $AFLGO/afl-fuzz -M main -z exp -c 45m -m none -k 120 -i in -o out$i ./xmllint --valid @@
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

    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
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

    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    cat $TMP_DIR/commit.diff | $SHOWLINENUM show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/tSrcs.txt

    # echo "" > $TMP_DIR/mydist.cfg.txt
    python $MYFUZZ/scripts/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt
    python $MYFUZZ/scripts/pyscripts/getChangeBBs.py $TMP_DIR

    export ADDITIONAL="-mydist=$TMP_DIR/mydist.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" ../configure --disable-shared --prefix=$(pwd)
    make clean all

    mkdir in
    cp $MYFUZZ/testcases/others/xml/small_document.xml in/

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep myfuzz | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "$MYFUZZ/afl-fuzz -S secondary -m none -k 120 -i in -o out$i ./xmllint --valid @@"
        $MYFUZZ/afl-fuzz -M main -m none -k 120 -i in -o out$i ./xmllint --valid @@
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