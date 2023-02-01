###
# @Author: Radon
# @Date: 2023-01-27 14:20:09
# @LastEditors: Radon
# @LastEditTime: 2023-01-30 13:52:49
# @Description: Hi, say something
###

for ((i = 1; i <= 20; i++)); do
    cd out$i/crashes
    if [ -f '0.txt' ]; then rm 0.txt; fi
    for f in $(ls | grep id); do echo -e "\n${f}" | cut -d ',' -f 1-3 >>0.txt | cat $f | /home/radon/Documents/fuzzing/CIProjs/binutils/ASAN/obj-asan/binutils/cxxfilt 2>&1 | egrep '(SUMMARY|#[0-9])' | tee -a 0.txt; done
    cd ../../
done
