###
# @Author: Radon
# @Date: 2022-06-10 14:19:33
 # @LastEditors: Radon
 # @LastEditTime: 2022-06-17 14:52:53
# @Description: jasper-CVE-2021-3443_26927, myfuzz parallel mode
###

main() {
    git clone https://github.com/mdadams/jasper.git SRC

    rm -rf jasper-a4dc77c
    cp -r SRC jasper-a4dc77c
    cd jasper-a4dc77c
    git checkout a4dc77c

    mkdir obj-myfuzz-2.52
    mkdir obj-myfuzz-2.52/temp

    export MYFUZZ=/home/radon/Documents/fuzzing/fuzzers/myfuzz-afl2.52b
    export SUBJECT=$PWD
    export TMP_DIR=$PWD/obj-myfuzz-2.52/temp
    export CC=$MYFUZZ/afl-clang-fast
    export CXX=$MYFUZZ/afl-clang-fast++
    export LDFLAGS=-lpthread
    export ADDITIONAL="-outdir=$TMP_DIR -fno-discard-value-names"

    cd obj-myfuzz-2.52
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
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

    # Get change lines
    git diff -U0 HEAD^ HEAD >$TMP_DIR/commit.diff
    cat $TMP_DIR/commit.diff | /home/radon/Documents/showlinenum/showlinenum.awk show_header=0 path=1 | grep -e "\.[ch]:[0-9]*:+" -e "\.cpp:[0-9]*:+" -e "\.cc:[0-9]*:+" | cut -d+ -f1 | rev | cut -c2- | cut -d/ -f1 | rev >$TMP_DIR/tSrcs.txt

    python /home/radon/Documents/project_vscode/cpp/llvm/4_LLVMPass/pyscripts/parse.py -p $TMP_DIR -d $TMP_DIR/dot-files -t $TMP_DIR/tSrcs.txt

    cd $SUBJECT
    mkdir obj-myfuzz-2.522
    cp -r obj-myfuzz-2.52/temp obj-myfuzz-2.522/temp
    rm -rf obj-myfuzz-2.52
    mv obj-myfuzz-2.522 obj-myfuzz-2.52
    cd obj-myfuzz-2.52
    export ADDITIONAL="-fitness=$TMP_DIR/fitness.cfg.txt"
    CFLAGS="$ADDITIONAL" CXXFLAGS="$ADDITIONAL" cmake ..
    make clean all

    mkdir in
    wget -P in https://github.com/Radon10043/myfuzz-afl2.52b/raw/master/testcases/my/jp2/not.jp2

    # Run [x] times
    for ((i = 1; i <= $1; i++)); do
        gnome-terminal -t "secondaey" -- bash -c "$MYFUZZ/afl-fuzz -S secondary -k 120 -i in -o out$i src/appl/jasper --output /tmp/out_s.jpg --input @@"
        $MYFUZZ/afl-fuzz -M main -m none -k 120 -i in -o out$i src/appl/jasper --output /tmp/out_m.jpg --input @@
    done
}

# Entry
# 第一个参数是数字, 表示重复fuzz多少次
if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "$1 is not a number."
    exit
fi

echo "$1 is a number, yeah!"

main $1
