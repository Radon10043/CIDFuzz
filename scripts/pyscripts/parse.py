'''
Author: Radon
Date: 2022-02-05 16:20:42
LastEditors: Radon
LastEditTime: 2023-02-22 15:38:07
Description: Hi, say something
'''
import argparse
import copy
import functools
import heapq
import json
import os
import sys
import time
from ast import arguments
from queue import PriorityQueue, Queue
from statistics import mean

import networkx as nx
import pydot

# Global
DU_VAR_DICT = dict()  # <行, <def/use, {变量}>>
BB_LINE_DICT = dict()  # <bb名, 它所包含的所有行>
BB_FUNC_DICT = dict()  # <bb名, 它所在的函数>
FUNC_ENTRY_DICT = dict()  # <函数名, 它的入口BB名字>
FUNC_PARAM_DICT = dict()  # <函数名, [形参列表]>
CALL_ARGS_DICT = dict()  # <行, <被调用的函数, [[实参]]>>
LINE_CALLS_PRE_DICT = dict()  # <调用的函数, <行, <形参, {实参}>>>
LINE_CALLS_BACK_DICT = dict()  # <行, <调用的函数, <形参, {实参}>>>
LINE_BB_DICT = dict()  # <行, 其所在基本块>
MAX_LINE_DICT = dict()  # <文件名, 其最大行数>

MAX_CONCERN_DIST = 63


class MyNode:

    def __init__(self, distance, nodeName, nodeLabel):
        self.distance = distance
        self.name = nodeName
        self.label = nodeLabel

    def __lt__(self, other):
        return self.distance < other.distance


def myCmp(x, y):
    """自定义排序, 行号大的排在前面

    Parameters
    ----------
    x : str
        filename:line
    y : str
        filename:line

    Returns
    -------
    int
        返回值必须是-1, 0, 1, 不能是True/False

    Notes
    -----
    _description_
    """
    x = int(x.split(":")[1])
    y = int(y.split(":")[1])

    if x > y:
        return -1
    elif x < y:
        return 1
    return 0


def isPreTainted(bbname: str, preSet: set):
    """查看该基本块是否被前向污染了

    Parameters
    ----------
    bbname : str
        基本块名称
    preSet : set
        前向污点分析时的变量集合
    defSet : set
        存储了各行定义的变量的集合
    useSet : set
        存储了各行使用的变量的集合

    Returns
    -------
    bool
        该基本块是否被前向污染
    set
        实时更新的前向污染变量集合

    Notes
    -----
    _description_
    """
    isTainted = False
    bbDuSet = preSet.copy()

    for bbline in BB_LINE_DICT[bbname]:
        try:
            if DU_VAR_DICT[bbline]["def"] & preSet:
                isTainted = True
                bbDuSet = bbDuSet - DU_VAR_DICT[bbline]["def"] | DU_VAR_DICT[bbline]["use"]
        except KeyError:
            continue  # 该行没有定义-使用关系, 跳过
    return isTainted, bbDuSet


def isBackTainted(bbname: str, backSet: set, backQueue: Queue, distance: int):
    """判断该基本块是否受到污染, 且若基本块所包含的行中调用了函数, 就加入到队列

    Parameters
    ----------
    bbname : str
        基本块名字
    backSet : set
        变量集合
    backQueue : Queue
        三元组队列
    distance : int
        该基本块与污点源之间的距离

    Returns
    -------
    _type_
        _description_

    Notes
    -----
    _description_
    """
    isTainted = False
    bbDuSet = backSet.copy()

    for bbline in reversed(BB_LINE_DICT[bbname]):
        # 查看该行是否调用了函数, 若调用了, 加入队列
        try:
            for calledF, pas in LINE_CALLS_BACK_DICT[bbline].items():
                targetLabel = FUNC_ENTRY_DICT[calledF]
                nBackSet = backSet.copy()
                for param, arguments in pas.items():
                    if nBackSet & arguments:
                        nBackSet -= arguments
                        nBackSet.add(param)
                if len(nBackSet) > 0:  # 如果更新后的变量集合为空的话, 加入队列也没有意义, 跳过
                    backQueue.put((targetLabel, distance, nBackSet))
        except KeyError:
            pass  # 该行没有调用函数

        # 根据每行的定义使用情况更新变量集合
        try:
            if DU_VAR_DICT[bbline]["use"] & bbDuSet:
                isTainted = True
                bbDuSet = bbDuSet - DU_VAR_DICT[bbline]["use"] | DU_VAR_DICT[bbline]["def"]
        except KeyError:
            pass  # 该行没有定义使用关系

    return isTainted, bbDuSet


def getbbPreTainted(loc: str, preSet: set):
    """根据行数获取基本块, 并更新变量污染信息

    Parameters
    ----------
    loc : str
        行数, filename:line
    preSet : set
        前向污染变量集合

    Returns
    -------
    str
        该行所属的基本块名称
    preSet
        实时更新的污染变量集合

    Notes
    -----
    _description_
    """
    # preSet |= DU_VAR_DICT[loc]["use"]  # 取并集, 为啥要这么做来着?

    filename, line = loc.split(":")
    line = int(line)

    while not loc in LINE_BB_DICT.keys() or loc != LINE_BB_DICT[loc]:
        # 倒序查看并更新污染变量集合
        line -= 1
        loc = filename + ":" + str(line)

        try:
            if DU_VAR_DICT[loc]["def"] & preSet:
                preSet = preSet - DU_VAR_DICT[loc]["def"] | DU_VAR_DICT[loc]["use"]
        except KeyError:
            continue  # 该行没有定义-使用关系, 跳过

    return loc


def getbbBackTainted(loc: str, backSet: set):
    """根据行数获取其所在基本块的污染情况

    Parameters
    ----------
    loc : str
        文件名:行数
    backSet : set
        变量集合

    Returns
    -------
    _type_
        _description_

    Notes
    -----
    _description_
    """
    bbname = LINE_BB_DICT[loc]

    filename, line = loc.split(":")
    line = int(line)

    while not loc in LINE_BB_DICT.keys() or loc != LINE_BB_DICT[loc]:
        # 顺序查看并更新污染变量集合
        line += 1
        loc = filename + ":" + str(line)

        if line > MAX_LINE_DICT[filename]:
            break  # 如果顺序遍历到文件末尾了, 跳出循环

        try:
            if DU_VAR_DICT[loc]["use"] & backSet:
                backSet = backSet - DU_VAR_DICT[loc]["use"] | DU_VAR_DICT[loc]["def"]
        except KeyError:
            continue  # 该行没有定义使用关系

    return bbname


def getNodeName(nodes, nodeLabel) -> str:
    """遍历nodes, 获取nodeLabel的name, 形如Node0x56372e651a90

    Parameters
    ----------
    nodes : _type_
        _description_
    nodeLabel : _type_
        _description_

    Returns
    -------
    str
        _description_

    Notes
    -----
    _description_
    """
    for node in nodes:
        if node.get("label") == "\"{" + nodeLabel + ":}\"":
            return node.obj_dict["name"]
    return ""


def distanceCalculation(path: str, dotPath: str, tSrcsFile: str):
    """计算各基本块的适应度

    Parameters
    ----------
    path : str
        _description_
    tSrcsFile : str
        _description_

    Notes
    -----
    _description_
    """
    tSrcs = dict()
    distDict = dict()  # <bb名, 适应度数组>
    resDict = dict()  # <bb名, 适应度>
    index = 0  # 下标

    global DU_VAR_DICT, BB_LINE_DICT, BB_FUNC_DICT, FUNC_ENTRY_DICT, FUNC_PARAM_DICT, CALL_ARGS_DICT
    global LINE_CALLS_PRE_DICT, LINE_CALLS_BACK_DICT, LINE_BB_DICT, MAX_LINE_DICT

    with open(path + "/duVar.json") as f:  # 读取定义使用关系的json文件
        DU_VAR_DICT = json.load(f)

        for k, v in DU_VAR_DICT.items():

            if "def" in v.keys():
                v["def"] = set(v["def"])

            if "use" in v.keys():
                v["use"] = set(v["use"])

    with open(path + "/bbLine.json") as f:  # 读取基本块和它所有报行的行的json文件
        BB_LINE_DICT = json.load(f)
    for k, v in BB_LINE_DICT.items():  # 对基本块所拥有的行进行排序, 从大到小, 方便后续操作
        v.sort(key=functools.cmp_to_key(myCmp))

    with open(path + "/bbFunc.json") as f:  # 该json是为了能更快地确认bb所在函数
        BB_FUNC_DICT = json.load(f)

    with open(path + "/funcEntry.json") as f:  # 该json是为了更方便地计算跨函数间的基本块距离
        FUNC_ENTRY_DICT = json.load(f)
        for k, v in FUNC_ENTRY_DICT.items():
            FUNC_ENTRY_DICT[k] = v.rstrip(":")

    with open(path + "/funcParam.json") as f:
        FUNC_PARAM_DICT = json.load(f)

    with open(path + "/callArgs.json") as f:
        CALL_ARGS_DICT = json.load(f)

    for line, vDict in CALL_ARGS_DICT.items():
        for func, args in vDict.items():
            if not func in FUNC_PARAM_DICT.keys():
                continue

            if len(FUNC_PARAM_DICT[func]) < 1:
                continue

            if not func in LINE_CALLS_PRE_DICT.keys():
                LINE_CALLS_PRE_DICT[func] = dict()
            LINE_CALLS_PRE_DICT[func][line] = dict()

            if not line in LINE_CALLS_BACK_DICT.keys():
                LINE_CALLS_BACK_DICT[line] = dict()
            LINE_CALLS_BACK_DICT[line][func] = dict()

            params = FUNC_PARAM_DICT[func]

            for i in range(min(len(params), len(args))):
                param = FUNC_PARAM_DICT[func][i]
                LINE_CALLS_PRE_DICT[func][line][param] = set(args[i])
                LINE_CALLS_BACK_DICT[line][func][param] = set(args[i])

    with open(path + "/linebb.json") as f:  # 该json存储了每一行对应的基本块
        LINE_BB_DICT = json.load(f)

    with open(path + "/maxLine.json") as f:
        MAX_LINE_DICT = json.load(f)

    with open(tSrcsFile) as f:
        lines = f.readlines()
        for line in lines:
            try:
                line = line.rstrip("\n")
                tSrcs[line] = copy.deepcopy(DU_VAR_DICT[line])
            except:
                pass

    for tk, tv in tSrcs.items():
        cgDist = 0  # 函数调用之间的距离
        visited = set()  # 防止重复计算

        preSet, backSet = set(), set()
        if "use" in tv.keys():
            preSet = tv["use"]
        if "def" in tv.keys():
            backSet = tv["def"]

        preQueue = Queue()  # 该队列的元素是一个三元组, 第一个元素是待分析的可以到达污点源的行, 第二个元素是函数间的距离, 第三个元素是受污染的变量
        if len(preSet):  # preSet为空时就不加入前向队列了, 因为没有意义
            preQueue.put((tk, cgDist, preSet))

        backQueue = Queue()
        if len(backSet):  # backSet为空时就不要加入后向队列里了, 因为没有意义
            backQueue.put((tk, cgDist, backSet))

        # 前向污点分析
        while not preQueue.empty():
            targetLabel, cgDist, preSet = preQueue.get()

            if targetLabel in visited or LINE_BB_DICT[targetLabel] in visited:
                print("Pre analyzing " + targetLabel + "..., Skip, len: ", preQueue.qsize())
                continue

            if cgDist > MAX_CONCERN_DIST:
                print("Pre analyzing " + targetLabel + "..., Skip, len: ", preQueue.qsize())
                visited.add(targetLabel)
                continue

            print("Pre analyzing " + targetLabel + "..., cgDist: ", cgDist, ", len: ", preQueue.qsize())

            try:
                targetLabel = getbbPreTainted(targetLabel, preSet)
            except:
                print("Hm, struct array?")
                continue

            func = BB_FUNC_DICT[targetLabel]
            cfg = "cfg." + func + ".dot"
            pq = PriorityQueue()

            cfgdot = pydot.graph_from_dot_file(dotPath + "/" + cfg)[0]
            cfgnx = nx.drawing.nx_pydot.from_pydot(cfgdot)
            nodes = cfgdot.get_nodes()

            targetName = getNodeName(nodes, targetLabel)

            entryLabel = FUNC_ENTRY_DICT[func]
            entryName = getNodeName(nodes, entryLabel)

            # 若无法获取target或entry的name, 跳过
            if len(targetName) == 0 or len(entryName) == 0:
                continue

            # 获取以污点源为终点, 能到达它的基本块, 达成前向分析的效果
            for node in nodes:
                # 有时候node.get完后是None? 这种情况下跳过
                try: nodeLabel = node.get("label").lstrip("\"{").rstrip(":}\"")
                except: continue
                nodeName = node.obj_dict["name"]

                if len(nodeLabel.split(":")) > 2:
                    nodeLabel = ":".join(nodeLabel.split(":")[0:2])

                try:
                    if nodeName == targetName:
                        distance = cgDist
                    else:
                        distance = cgDist + nx.shortest_path_length(cfgnx, nodeName, targetName)
                    pq.put(MyNode(distance, nodeName, nodeLabel))
                except nx.NetworkXNoPath:
                    pass

            nowDist = cgDist  # nowDist用于判断当前节点与上一节点是否是同一宽度
            bbSumDuSet = set()
            while not pq.empty():
                node = pq.get()
                distance, bbname = node.distance, node.label

                # 同一宽度时, 统计def-use情况, 并存入集合
                # 不同宽度时, 与defSet做差集, 与useSet做并集
                if distance != nowDist:
                    nowDist = distance
                    preSet = bbSumDuSet.copy()
                    bbSumDuSet.clear()

                # 如果距离与cg间的距离相等, 证明该基本块就是污点源基本块或调用里能到达污点源函数的基本块, 一定是被污染的
                if distance == cgDist:
                    isTainted = True
                    bbSumDuSet = preSet.copy()
                else:
                    # 有的基本块是LLVM自动补充的, 和源文件的位置对应不上, 分析它是否受污染的话会出错
                    # 因此这种基本块默认为没有受污染
                    try:
                        isTainted, bbDuSet = isPreTainted(bbname, preSet)
                        bbSumDuSet |= bbDuSet
                    except:
                        isTainted = False

                # 跳过距离超过MAX_CONCERN_DIST的基本块
                if distance > MAX_CONCERN_DIST:
                    continue

                # 若被污染了, 加入distDict
                if isTainted:
                    if not bbname in distDict.keys():  # 将value初始化为长度为len(tSrcs)的列表
                        distDict[bbname] = [-1] * len(tSrcs)
                    if distDict[bbname][index] == -1:   # 初始值是-1, -1表示没有被第index个变更点污染
                        distDict[bbname][index] = distance
                    else:
                        distDict[bbname][index] = min(distDict[bbname][index], distance)

            cgDist += nx.shortest_path_length(cfgnx, entryName, targetName)

            # 如果没有函数调用了func, 证明前向分析到头了, 不需要再往队列里添加元素了
            if not func in LINE_CALLS_PRE_DICT.keys():
                visited.add(targetLabel)
                continue

            # 将调用了当前函数的bb和cgDist加入队列
            for caller, pas in LINE_CALLS_PRE_DICT[func].items():
                # 根据调用函数的对应关系替换preSet
                nPreSet = preSet.copy()
                for param, arguments in pas.items():
                    try:
                        nPreSet.remove(param)
                        nPreSet |= arguments
                    except KeyError:  # 若param没有受到污染, 跳过
                        pass
                preQueue.put((caller, cgDist, nPreSet))

            # 将该污点源加入集合, 防止重复计算
            visited.add(targetLabel)

        # 后向污点分析
        visited = set()
        while not backQueue.empty():
            targetLabel, cgDist, backSet = backQueue.get()

            if targetLabel in visited or LINE_BB_DICT[targetLabel] in visited:
                print("Back analyzing " + targetLabel + "..., Skip, len: ", backQueue.qsize())
                continue

            if cgDist > MAX_CONCERN_DIST:
                print("Back analyzing " + targetLabel + "..., Skip, len: ", backQueue.qsize())
                continue

            print("Back analyzing " + targetLabel + "..., cgDist: ", cgDist, ", len: ", backQueue.qsize())

            targetLabel = getbbBackTainted(targetLabel, backSet)

            func = BB_FUNC_DICT[targetLabel]
            cfg = "cfg." + func + ".dot"
            pq = PriorityQueue()

            cfgdot = pydot.graph_from_dot_file(dotPath + "/" + cfg)[0]
            cfgnx = nx.drawing.nx_pydot.from_pydot(cfgdot)
            nodes = cfgdot.get_nodes()

            targetName = getNodeName(nodes, targetLabel)

            # 若无法获取target的name, 跳过
            if len(targetName) == 0:
                visited.add(targetLabel)
                continue

            # 获取以污点源为起点, 能被它到达的基本块, 达成后向污点分析的效果
            for node in nodes:
                # 有时候node.get完后是None? 这种情况下跳过
                try: nodeLabel = node.get("label").lstrip("\"{").rstrip(":}\"")
                except: continue
                nodeName = node.obj_dict["name"]

                if len(nodeLabel.split(":")) > 2:
                    nodeLabel = ":".join(nodeLabel.split(":")[0:2])

                try:
                    if nodeName == targetName:
                        distance = cgDist
                    else:
                        distance = nx.shortest_path_length(cfgnx, targetName, nodeName) + cgDist
                    pq.put(MyNode(distance, nodeName, nodeLabel))
                except nx.NetworkXNoPath:
                    pass  # 无法到达, 跳过

            nowDist = cgDist
            bbSumDuSet = set()
            while not pq.empty():
                node = pq.get()
                distance, bbname = node.distance, node.label

                # 同一宽度时, 根据每个bb的def-use对backSet的拷贝bbDuSet进行更新, 并将结果都存入bbSumDuSet
                # 不同宽度时, 将bbSumDuSet的值拷贝到backSet
                if distance != nowDist:
                    nowDist = distance
                    backSet = bbSumDuSet.copy()
                    bbSumDuSet.clear()

                # 有的基本块是LLVM自动补充的, 和源文件的位置对应不上, 分析它是否受污染的话会出错
                # 因此这种基本块默认为没有受污染
                try:
                    isTainted, bbDuSet = isBackTainted(bbname, backSet, backQueue, distance)
                    bbSumDuSet |= bbDuSet
                except:
                    isTainted = False

                if distance == cgDist:
                    isTainted = True

                # 跳过距离超过MAX_CONCERN_DIST的基本块
                if distance > MAX_CONCERN_DIST:
                    continue

                # 若被污染了, 计算适应度, 加入dict
                if isTainted:
                    if not bbname in distDict.keys():  # 将value初始化为长度为len(tSrcs)的列表
                        distDict[bbname] = [-1] * len(tSrcs)
                    if distDict[bbname][index] == -1:   # 初始值是-1, -1表示没有被第index个变更点污染
                        distDict[bbname][index] = distance
                    else:
                        distDict[bbname][index] = min(distDict[bbname][index], distance)

            visited.add(targetLabel)

        index += 1

    print("Calculating average ...")

    for bb, dists in distDict.items():
        dists = [dist for dist in dists if dist != -1]
        resDict[bb] = min(dists)

    with open(os.path.join(path, "cidist.cfg.txt"), mode="w") as f:
        for bb, dist in resDict.items():
            f.write(bb + "," + str(dist) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--path", help="存储json, txt等文件的目录", required=True)
    parser.add_argument("-d", "--dot", help="存储dot文件的目录", required=True)
    parser.add_argument("-t", "--taint", help="存储污点源信息的txt文件", required=True)
    args = parser.parse_args()

    start = time.time()
    distanceCalculation(args.path, args.dot, args.taint)
    end = time.time()
    print("Calculation is finished, consumed %f seconds." % (end - start))
