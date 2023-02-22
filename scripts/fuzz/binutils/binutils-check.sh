###
# @Author: Radon
# @Date: 2023-01-27 14:20:09
# @LastEditors: Radon
# @LastEditTime: 2023-02-22 15:12:57
# @Description: Hi, say something
###

asan() {
    for ((i = 1; i <= 20; i++)); do
        cd out$i/crashes
        if [ -f '0.asan.txt' ]; then rm 0.asan.txt; fi
        cnt=0
        for f in $(ls | grep id); do
            echo -n 'Analyzing out'$i' ... '$cnt$'\r'
            echo -e "\n${f}" | cut -d ',' -f 1-3 >>0.asan.txt
            cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/ASAN/obj-asan/binutils/cxxfilt 2>&1 | egrep '(SUMMARY|#[0-9]|Hint)' | tee -a 0.asan.txt >/dev/null
            ((cnt++))
        done
        echo
        cd ../../
    done
}

patch() {
    for ((i = 1; i <= 20; i++)); do
        cd out$i/crashes
        if [ -f '0.patch.'$1'.txt' ]; then rm 0.patch.$1.txt; fi
        cnt=0
        for f in $(ls | grep id); do
            echo -e "\n${f}" | cut -d ',' -f 1-3 >>0.patch.$1.txt
            cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/PATCH-2016-$1/obj-build/binutils/cxxfilt >/dev/null 2>&1
            extnum=$?

            echo $extnum >>0.patch.$1.txt
            if [ $extnum -eq 0 ]; then
                echo -n 'Analyzing out'$i' ... '$cnt$' ... yeah!\r'
                break
            fi

            echo -n 'Analyzing out'$i' ... '$cnt$'\r'
            ((cnt++))
        done
        echo
        cd ../../
    done
}

FUZZER=asan-skip-det/afl
NUMBERS=(4487 4489 4490 4491 4492 6131)

for NUMBER in ${NUMBERS[@]}; do
    if [ ! -d 'PATCH-2016-'$NUMBER ]; then
        echo "Directory PATCH-2016-"$NUMBER" doesn't exist!"
        exit 1
    fi
done

cd res/$FUZZER
for NUMBER in ${NUMBERS[@]}; do
    if [ $NUMBER -eq 4488 ]; then
        echo "Analyzing $NUMBER in ASAN ..."
        asan
    else
        echo "Analyzing $NUMBER ..."
        patch $NUMBER
    fi
done
