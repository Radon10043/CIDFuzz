###
# @Author: Radon
# @Date: 2022-06-17 12:17:21
# @LastEditors: Radon
# @LastEditTime: 2023-02-22 16:59:50
# @Description: Hi, say something
###

download() {
    git clone https://github.com/mdadams/jasper.git SRC

    rm -rf jasper-07856c3
    cp -r SRC jasper-07856c3
    cd jasper-07856c3
    git checkout 07856c3
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

    echo $'jas_cm.c:1141\njas_cm.c:1146\njas_cm.c:1149\njas_cm.c:1152\njas_cm.c:1157\njas_cm.c:1160\njas_cm.c:1163\njas_cm.c:1166\njas_cm.c:313\njas_cm.c:314\njas_cm.c:317\njas_cm.c:318\njp2_dec.c:322\njp2_dec.c:325' >$TMP_DIR/changeBBs.txt

    cd obj-afl-2.52
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
    make clean all

    mkdir in
    cp $AFL/testcases/images/bmp/not_kitty.bmp in
    cp $AFL/testcases/images/jp2/not_kitty.jp2 in

    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep afl | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "timeout 2h $AFL/afl-fuzz -S secondary -m none -i in -o out$i src/app/jasper --output /tmp/out_s.jpg --input @@" &
        timeout 2h $AFL/afl-fuzz -M main -m none -i in -o out$i src/app/jasper --output /tmp/out_m.jpg --input @@
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
    echo $'jas_cm.c:1141\njas_cm.c:1146\njas_cm.c:1149\njas_cm.c:1152\njas_cm.c:1157\njas_cm.c:1160\njas_cm.c:1163\njas_cm.c:1166\njas_cm.c:313\njas_cm.c:314\njas_cm.c:317\njas_cm.c:318\njp2_dec.c:322\njp2_dec.c:325' >$TMP_DIR/BBtargets.txt

    echo $'jas_cm.c:1141\njas_cm.c:1146\njas_cm.c:1149\njas_cm.c:1152\njas_cm.c:1157\njas_cm.c:1160\njas_cm.c:1163\njas_cm.c:1166\njas_cm.c:313\njas_cm.c:314\njas_cm.c:317\njas_cm.c:318\njp2_dec.c:322\njp2_dec.c:325' >$TMP_DIR/changeBBs.txt

    cd obj-aflgo
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
    make clean all

    cat $TMP_DIR/BBnames.txt | rev | cut -d: -f2- | rev | sort | uniq >$TMP_DIR/BBnames2.txt && mv $TMP_DIR/BBnames2.txt $TMP_DIR/BBnames.txt
    cat $TMP_DIR/BBcalls.txt | sort | uniq >$TMP_DIR/BBcalls2.txt && mv $TMP_DIR/BBcalls2.txt $TMP_DIR/BBcalls.txt

    cd src/app
    $AFLGO/scripts/genDistance.sh $SUBJECT $TMP_DIR

    cd $SUBJECT
    mkdir obj-aflgo2
    cp -r obj-aflgo/temp obj-aflgo2/temp
    rm -rf obj-aflgo
    mv obj-aflgo2 obj-aflgo
    cd obj-aflgo

    export ADDITIONAL="-distance=$TMP_DIR/distance.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
    make clean all

    mkdir in
    cp $AFLGO/testcases/images/bmp/not_kitty.bmp in
    cp $AFLGO/testcases/images/jp2/not_kitty.jp2 in

    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep aflgo | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "timeout 2h $AFLGO/afl-fuzz -S secondary -m none -z exp -c 45m -i in -o out$i src/app/jasper --output /tmp/out_m.jpg --input @@" &
        $timeout 2h AFLGO/afl-fuzz -M main -m none -z exp -c 45m -i in -o out$i src/app/jasper --output /tmp/out_m.jpg --input @@
    done
}

myfuzz() {
    mkdir obj-myfuzz-2.52
    mkdir obj-myfuzz-2.52/temp

    export CIDFUZZ=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-myfuzz-2.52/temp
    export CC=$CIDFUZZ/afl-clang-fast
    export CXX=$CIDFUZZ/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-outdir=$TMP_DIR -fno-discard-value-names -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps"

    cd obj-myfuzz-2.52
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
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

    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    cat $TMP_DIR/commit.diff | $SHOWLINENUM show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/tSrcs.txt

    python $CIDFUZZ/scripts/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt

    # echo $'' >$TMP_DIR/changeBBs.txt
    python $CIDFUZZ/scripts/pyscripts/getChangeBBs.py $TMP_DIR

    cd $SUBJECT
    mkdir obj-myfuzz-2.522
    cp -r obj-myfuzz-2.52/temp obj-myfuzz-2.522/temp
    rm -rf obj-myfuzz-2.52
    mv obj-myfuzz-2.522 obj-myfuzz-2.52
    cd obj-myfuzz-2.52
    export ADDITIONAL="-cidist=$TMP_DIR/cidist.cfg.txt -changes=$TMP_DIR/changeBBs.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
    make clean all

    mkdir in
    cp $CIDFUZZ/testcases/images/bmp/not_kitty.bmp in
    cp $CIDFUZZ/testcases/images/jp2/not_kitty.jp2 in

    for ((i = 1; i <= $1; i++)); do
        while [ $(ps -ax | grep myfuzz | wc -l) -gt 1 ]; do
            echo "Secondary still running? sleep 1 minute ..."
            sleep 1m
        done
        gnome-terminal -t "secondary" -- bash -c "timeout 2h $CIDFUZZ/afl-fuzz -S secondary -m none -i in -o out$i src/app/jasper --output /tmp/out_s.jpg --input @@" &
        timeout 2h $CIDFUZZ/afl-fuzz -M main -m none -i in -o out$i src/app/jasper --output /tmp/out_m.jpg --input @@
    done
}

# Entry
# 第一个参数是afl, aflgo或myfuzz
# 第二个参数表示重复fuzz多少次

download

if ! [[ "$2" =~ ^[0-9]+$ ]]; then
    echo "$2 is not a number."
    exit
fi

export SHOWLINENUM=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b/scripts/showlinenum.awk
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
