'''
Author: Radon
Date: 2022-06-17 17:26:12
LastEditors: Radon
LastEditTime: 2022-06-17 18:06:48
Description: Get change bbs
'''
from bisect import bisect
import sys
import os


def getChangeBBs(taints: list, bbs: list) -> list:
    bbDict = dict()  # <str, list<int>>: <文件名, 行列表(从小到大)>
    changeBBs = set()  # set<str>: 存储了包含变更点的各bb

    for bb in bbs:
        try:
            filename, line = bb.split(":")
            line = int(line)
            if not filename in bbDict.keys():
                bbDict[filename] = list()
            bbDict[filename].append(line)
        except:
            print("Error? ->", bb)

    for k, v in bbDict.items():
        v.sort()

    for taint in taints:
        try:
            tFile, tLine = taint.split(":")
            tLine = int(tLine)
            idx = bisect(bbDict[tFile], tLine)
            if idx > 0:
                changeBBs.add(tFile + ":" + str(bbDict[tFile][idx - 1]))        # 这里有时候会把更改了注释但没改代码的块算进去
        except:
            print("Error? ->", taint)

    changeBBs = list(changeBBs)
    changeBBs.sort()
    return changeBBs


if __name__ == "__main__":
    tmpDir = sys.argv[1]  # TMP_DIR的路径, 其中存储了tSrcs和BBnames

    taints = list()
    bbs = list()

    # 读取污点源和所有基本块名
    with open(os.path.join(tmpDir, "tSrcs.txt")) as f:
        lines = f.readlines()
        for line in lines:
            taints.append(line.rstrip("\n"))
    with open(os.path.join(tmpDir, "BBnames.txt")) as f:
        lines = f.readlines()
        for line in lines:
            bbs.append(line.rstrip("\n"))

    changeBBs = getChangeBBs(taints, bbs)

    with open(os.path.join(tmpDir, "changeBBs.txt"), mode="w") as f:
        for bb in changeBBs:
            f.write(bb + "\n")

    print("Finish?")