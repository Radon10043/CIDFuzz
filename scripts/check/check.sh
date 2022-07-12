###
# @Author: Radon
# @Date: 2022-07-12 14:29:25
# @LastEditors: Radon
# @LastEditTime: 2022-07-12 14:29:59
# @Description: Hi, say something
###

usage() {
    echo "这个脚本递归检查参数1所表示的路径下的所有chg_cov_tend.txt,"
    echo "并输出第一行中\"stop time:\"后的内容到check_result.txt"
    echo "参数1: 要检查的路径"
}

check_file() {
    black_list="queue crashes hangs"
    for name in ${black_list}; do
        if [[ "$1" =~ "$name" ]]; then
            return
        fi
    done

    echo "Checking $1 ..."

    for file in $(ls $1); do
        if [ -f $1"/"$file ]; then
            path=$1"/"$file
            if [ "$file" == "chg_cov_tend.txt" ]; then
                key=$(echo $path$': ' | rev | cut -d "/" -f 1-4 | rev)
                value=$(head -n 1 $path | cut -d ":" -f 2)
                echo $key$value >>check_result.txt
            fi
        else
            check_file $1"/"$file
        fi
    done
}

if [ ! -n "$1" ]; then
    usage
    exit
fi

echo "" >check_result.txt
check_file $1
