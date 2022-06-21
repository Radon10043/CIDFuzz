/*
   american fuzzy lop - LLVM-mode instrumentation pass
   ---------------------------------------------------

   Written by Laszlo Szekeres <lszekeres@google.com> and
              Michal Zalewski <lcamtuf@google.com>

   LLVM integration design comes from Laszlo Szekeres. C bits copied-and-pasted
   from afl-as.c are Michal's fault.

   Copyright 2015, 2016 Google Inc. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at:

     http://www.apache.org/licenses/LICENSE-2.0

   This library is plugged into LLVM when invoking clang through afl-clang-fast.
   It tells the compiler to add code roughly equivalent to the bits discussed
   in ../afl-as.h.

 */

#define AFL_LLVM_PASS

#include "../config.h"
#include "../debug.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <map>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <list>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "llvm/ADT/Statistic.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"
#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Analysis/CFGPrinter.h"
#include "llvm/Support/JSON.h"

#if defined(LLVM34)
#include "llvm/DebugInfo.h"
#else
#include "llvm/IR/DebugInfo.h"
#endif

#if defined(LLVM34) || defined(LLVM35) || defined(LLVM36)
#define LLVM_OLD_DEBUG_API
#endif

using namespace llvm;

/* 全局变量 */
std::map<std::string, std::map<std::string, std::set<std::string>>> duVarMap;                                // 存储变量的def-use信息的map: <文件名与行号, <def/use, 变量>>
std::map<Value *, std::string> dbgLocMap;                                                                    // 存储指令和其对应的在源文件中位置的map, <指令, 文件名与行号>
std::map<std::string, std::vector<std::string>> funcParamMap;                                                // 存储函数和其形参的map, 用这个map主要是为了防止出现跨文件调用函数时参数丢失的问题
std::map<std::string, std::map<std::string, std::vector<std::set<std::string>>>> callArgsMap;                // <行, <调用的函数, 实参>>
std::map<std::string, std::set<std::string>> bbLineMap;                                                      // 存储bb和其所包含所有行的map, <bb名字, 集合(包含的所有行)>
std::map<std::string, std::string> funcEntryMap;                                                             // <函数名, 其cfg中入口BB的名字>
std::map<std::string, std::string> bbFuncMap;                                                                // <bb名, 其所在函数名>
std::map<std::string, std::string> linebbMap;                                                                // <行, 其所在bb>
std::map<std::string, int> maxLineMap;                                                                       // <filename, 文件行数>

cl::opt<std::string> MyDistFile(
    "mydist",
    cl::desc("MyDist file containing the mydist of each basic block to the provided targets."),
    cl::value_desc("filename")
);

cl::opt<std::string> OutDirectory(
    "outdir",
    cl::desc("Output directory where json files are generated."),
    cl::value_desc("outdir"));

cl::opt<std::string> ChangesFile(
    "changes",
    cl::desc("A file which store change bb's name."),
    cl::value_desc("changes"));

namespace llvm {

template<>
struct DOTGraphTraits<Function*> : public DefaultDOTGraphTraits {
  DOTGraphTraits(bool isSimple=true) : DefaultDOTGraphTraits(isSimple) {}

  static std::string getGraphName(Function *F) {
    return "CFG for '" + F->getName().str() + "' function";
  }

  std::string getNodeLabel(BasicBlock *Node, Function *Graph) {
    if (!Node->getName().empty()) {
      return Node->getName().str();
    }

    std::string Str;
    raw_string_ostream OS(Str);

    Node->printAsOperand(OS, false);
    return OS.str();
  }
};

} // namespace llvm

namespace {

  class AFLCoverage : public ModulePass {

    public:

      static char ID;
      AFLCoverage() : ModulePass(ID) { }

      bool runOnModule(Module &M) override;

      // StringRef getPassName() const override {
      //  return "American Fuzzy Lop Instrumentation";
      // }

  };

}


char AFLCoverage::ID = 0;


static void getDebugLoc(const Instruction *I, std::string &Filename,
                        unsigned &Line) {
#ifdef LLVM_OLD_DEBUG_API
  DebugLoc Loc = I->getDebugLoc();
  if (!Loc.isUnknown()) {
    DILocation cDILoc(Loc.getAsMDNode(M.getContext()));
    DILocation oDILoc = cDILoc.getOrigLocation();

    Line = oDILoc.getLineNumber();
    Filename = oDILoc.getFilename().str();

    if (filename.empty()) {
      Line = cDILoc.getLineNumber();
      Filename = cDILoc.getFilename().str();
    }
  }
#else
  if (DILocation *Loc = I->getDebugLoc()) {
    Line = Loc->getLine();
    Filename = Loc->getFilename().str();

    if (Filename.empty()) {
      DILocation *oDILoc = Loc->getInlinedAt();
      if (oDILoc) {
        Line = oDILoc->getLine();
        Filename = oDILoc->getFilename().str();
      }
    }
  }
#endif /* LLVM_OLD_DEBUG_API */
}

static bool isBlacklisted(const Function *F) {
  static const SmallVector<std::string, 8> Blacklist = {
    "asan.",
    "llvm.",
    "sancov.",
    "__ubsan_handle_",
    "free",
    "malloc",
    "calloc",
    "realloc"
  };

  for (auto const &BlacklistFunc : Blacklist) {
    if (F->getName().startswith(BlacklistFunc)) {
      return true;
    }
  }

  return false;
}

/**
 * @brief 向前搜索获得用到的变量名
 *
 * @param op
 * @param varName
 */
static void fsearchVar(Instruction::op_iterator op, std::string &varName) {

  if (GlobalVariable *GV = dyn_cast<GlobalVariable>(op))
    varName = GV->getName().str();

  if (Instruction *Inst = dyn_cast<Instruction>(op)) {

    varName = Inst->getName().str();

    if (Inst->getOpcode() == Instruction::PHI) // ?
      return;

    for (auto nop = Inst->op_begin(); nop != Inst->op_end(); nop++)
      fsearchVar(nop, varName);
  }
}

/**
 * @brief 向前搜索获得用到的变量名和它的类型
 *
 * @param op
 * @param varName
 * @param varType
 */
static void fsearchVar(Instruction::op_iterator op, std::string &varName, Type *&varType) {

  if (GlobalVariable *GV = dyn_cast<GlobalVariable>(op))
    varName = GV->getName().str();

  if (Instruction *Inst = dyn_cast<Instruction>(op)) {

    varName = Inst->getName().str();
    varType = Inst->getType();

    if (Inst->getOpcode() == Instruction::PHI) // ?
      return;

    for (auto nop = Inst->op_begin(); nop != Inst->op_end(); nop++)
      fsearchVar(nop, varName);
  }
}

/**
 * @brief 向前搜索, 获得函数参数对应的变量集合
 *
 * @param op
 * @param varName
 * @param vars
 */
static void fsearchCall(Instruction::op_iterator op, std::string &varName, std::set<std::string> &vars) {

  if (GlobalVariable *GV = dyn_cast<GlobalVariable>(op))
    varName = GV->getName().str();

  if (Instruction *Inst = dyn_cast<Instruction>(op)) {

    varName = Inst->getName().str();

    for (auto op = Inst->op_begin(); op != Inst->op_end(); op++)
      fsearchCall(op, varName, vars);

  } else if (!varName.empty()) {

    size_t found = varName.find(".addr");
    if (found != std::string::npos)
      varName = varName.substr(0, found);

    vars.insert(varName);
  }
}


bool AFLCoverage::runOnModule(Module &M) {

  bool is_preprocessing = false;
  std::unordered_map<std::string, u64> distMap;
  std::unordered_set<std::string> bbset;

  /* 不能同时指定 -mydist 与 -outdir */

  if (!MyDistFile.empty() && !OutDirectory.empty()) {
    FATAL("Cannot specify both '-mydist' and '-outdir'!");
    return false;
  }

  if (!OutDirectory.empty()) {

    /* 若 -outdir 不为空, 则认为是预处理模式 */

    is_preprocessing = true;

  } else if (!MyDistFile.empty()) {

    std::ifstream fin(MyDistFile);
    std::string bbAndDist;

    if (fin.is_open()) {

      while (getline(fin, bbAndDist)) {

        /* 查询一行中逗号所在位置, 若没有, 跳过 */

        size_t pos = bbAndDist.find(",");
        if (pos == std::string::npos)
          continue;

        /* 获取bbname与适应度*100后的值, 存入map与set */

        std::string bbname = bbAndDist.substr(0, pos);
        int mydist         = (int) (atof(bbAndDist.substr(pos + 1).c_str()));
        distMap[bbname]    = mydist;
        bbset.insert(bbname);

      }

      fin.close();

    } else {

      FATAL("Hmmm, I can't find mydist file.");
      return false;

    }

  }

#ifdef CHECK_COV
  /* Get change bbs */

  std::vector<std::string> changes;   // 存储所有变更基本块的vector

  if (!ChangesFile.empty()) {

    std::string changeBB;
    std::ifstream fin(ChangesFile);

    if (fin.is_open()) {

      while (getline(fin, changeBB)) {

        if (!changeBB.empty())
          changes.emplace_back(changeBB);

      }

    } else {

      FATAL("Hmmm, I can't find changes file.");
      return false;

    }

  }
#endif

  /* Show a banner */

  char be_quiet = 0;

  if (isatty(2) && !getenv("AFL_QUIET")) {

    SAYF(cCYA "afl-llvm-pass " cBRI VERSION cRST " modified by Radon (%s mode)\n",
        (is_preprocessing ? "preprocessing" : "mydist instrumentation"));

  } else be_quiet = 1;

  /* Decide instrumentation ratio */

  char* inst_ratio_str = getenv("AFL_INST_RATIO");
  unsigned int inst_ratio = 100;

  if (inst_ratio_str) {

    if (sscanf(inst_ratio_str, "%u", &inst_ratio) != 1 || !inst_ratio ||
        inst_ratio > 100)
      FATAL("Bad value of AFL_INST_RATIO (must be between 1 and 100)");

  }

  int inst_blocks = 0;

  if (is_preprocessing) {

    /* Preprocessing mode */

    std::ofstream bbnames(OutDirectory + "/BBnames.txt", std::ofstream::out | std::ofstream::app);
    std::ofstream bbcalls(OutDirectory + "/BBcalls.txt", std::ofstream::out | std::ofstream::app);
    std::ofstream fnames(OutDirectory + "/Fnames.txt", std::ofstream::out | std::ofstream::app);

    /* Create dot-files directory */

    std::string dotfiles(OutDirectory + "/dot-files");
    if (sys::fs::create_directory(dotfiles)) {
      FATAL("Could not create directory %s.", dotfiles.c_str());
    }

    /* Def-use */

    for (auto &F : M) {

      if (isBlacklisted(&F))
        continue;

      /* 获取函数的Param列表, 防止出现跨文件调用函数时参数丢失的问题 */

      std::vector<std::string> paramVec;
      bool hasEmptyParam = false;
      for (auto arg = F.arg_begin(); arg != F.arg_end(); arg++) {
        std::string paramName = arg->getName().str(); // 虽然是arg->getName(), 但实际上获得的是param的name
        if (paramName.empty()) {
          hasEmptyParam = true;
          break;
        }
        paramVec.emplace_back(arg->getName().str());
      }

      /* 不存在空形参名的话, 就加入到map */

      if (!hasEmptyParam)
        funcParamMap[F.getName().str()] = paramVec;

      for (auto &BB : F) {

        std::string bbname;

        for (auto &I : BB) {

          /* 跳过external libs */

          std::string filename;
          unsigned line;
          getDebugLoc(&I, filename, line);
          static const std::string Xlibs("/usr/");
          if (!filename.compare(0, Xlibs.size(), Xlibs))
            continue;

          /* 仅保留文件名与行号 */

          std::size_t found = filename.find_last_of("/\\");
          if (found != std::string::npos)
            filename = filename.substr(found + 1);

          /* 获取当前位置 */

          std::string loc = filename + ":" + std::to_string(line);

          /* 设置基本块名字 */

          if (!filename.empty() && line) {

            if (bbname.empty()) { // 若基本块名字为空时, 设置基本块名字, 并将其加入到bbFuncMap
              bbname = filename + ":" + std::to_string(line);
              bbFuncMap[bbname] = F.getName().str();
            }

            if (!bbname.empty()) { // 若基本块名字不为空, 将该行加入到map
              bbLineMap[bbname].insert(loc);
              linebbMap[loc] = bbname;
          }

            dbgLocMap[&I] = loc;
            maxLineMap[filename] = maxLineMap[filename] > line ? maxLineMap[filename] : line;
          } else
            continue;


          /* 获取函数调用信息 */

          if (auto *c = dyn_cast<CallInst>(&I)) {
            if (auto *CalledF = c->getCalledFunction()) {
              if (!isBlacklisted(CalledF)) {

                /* 按顺序获得调用函数时其形参对应的变量 */

                std::vector<std::set<std::string>> varVec;
                for (auto op = I.op_begin(); op != I.op_end(); op++) {
                  std::set<std::string> vars; // 形参对应的变量可能是多个, 所以存到一个集合中
                  std::string varName("");
                  fsearchCall(op, varName, vars);
                  varVec.push_back(vars);
                }

                /* 将函数和其参数对应的信息写入map */

                for (int i = 0; i < CalledF->arg_size(); i++) {
                  if (i > varVec.size())
                    break;
                  callArgsMap[loc][CalledF->getName().str()].push_back(varVec[i]);
                }
              }
            }
          }

          /* 分析变量的定义-使用关系 */

          std::string varName;
          switch (I.getOpcode()) {

            case Instruction::Store: { // Store表示对内存有修改, 所以是def

              std::vector<std::string> varNames; // 存储Store指令中变量出现的顺序
              for (auto op = I.op_begin(); op != I.op_end(); op++) {
                fsearchVar(op, varName);
                varNames.push_back(varName);
              }

              int n = varNames.size(); // 根据LLVM官网的描述, n的值应该为2, 因为Store指令有两个参数, 第一个参数是要存储的值(use), 第二个指令是要存储它的地址(def)
              for (int i = 0; i < n - 1; i++) {
                if (varNames[i].empty()) // 若分析得到的变量名为空, 则不把空变量名存入map, 下同
                  continue;
                duVarMap[dbgLocMap[&I]]["use"].insert(varNames[i]);
              }

              if (n < 2) outs() << "Hm???????????\n";

              if (varNames[n - 1].empty())
                break;

              duVarMap[dbgLocMap[&I]]["def"].insert(varNames[n - 1]);

              break;
            }

            case Instruction::Load: { // load表示从内存中读取, 所以是use

              for (auto op = I.op_begin(); op != I.op_end(); op++)
                fsearchVar(op, varName);

              if (varName.empty())
                break;

              duVarMap[dbgLocMap[&I]]["use"].insert(varName);

              break;
            }

            case Instruction::Call: { // 调用函数时用到的变量也加入到def-use的map中

              Type *varType = I.getType();

              for (auto op = I.op_begin(); op != I.op_end(); op++) {
                fsearchVar(op, varName, varType);

                if (varName.empty())
                  continue;

                if (varType->isPointerTy()) { // 如果是指针传递, 则认为 def,use 都有
                  duVarMap[dbgLocMap[&I]]["def"].insert(varName);
                  duVarMap[dbgLocMap[&I]]["use"].insert(varName);
                } else {
                  duVarMap[dbgLocMap[&I]]["use"].insert(varName);
                }
              }

              break;
            }
          }
        }
      }
    }

    int fileIdx = 0;
    for (; ; fileIdx++) {
      std::fstream tmpF(OutDirectory + "/duVar" + std::to_string(fileIdx) + ".json");
      if (!tmpF)
        break;
    }

    /* 将duVarMap转换为json并输出 */

    std::error_code EC;
    raw_fd_ostream duVarJson(OutDirectory + "/duVar" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream duVarJ(duVarJson);
    duVarJ.objectBegin();
    for (auto it = duVarMap.begin(); it != duVarMap.end(); it++) { // 遍历map并转换为json, llvm的json似乎不会自动格式化?
      duVarJ.attributeBegin(it->first);
      duVarJ.objectBegin();
      for (auto iit = it->second.begin(); iit != it->second.end(); iit++) {
        duVarJ.attributeBegin(iit->first);
        duVarJ.arrayBegin();
        for (auto var : iit->second) {
          size_t found = var.find(".addr");
          if (found != std::string::npos)
            var = var.substr(0, found);
          duVarJ.value(var);
        }
        duVarJ.arrayEnd();
        duVarJ.attributeEnd();
      }
      duVarJ.objectEnd();
      duVarJ.attributeEnd();
    }
    duVarJ.objectEnd();

    /* 将bbLineMap转为json并输出 */

    raw_fd_ostream bbLineJson(OutDirectory + "/bbLine" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream bbLineJ(bbLineJson);
    bbLineJ.objectBegin();
    for (auto it = bbLineMap.begin(); it != bbLineMap.end(); it++) {
      bbLineJ.attributeBegin(it->first);
      bbLineJ.arrayBegin();
      for (auto line : it->second)
        bbLineJ.value(line);
      bbLineJ.arrayEnd();
      bbLineJ.attributeEnd();
    }
    bbLineJ.objectEnd();

    /* 将linebbMap转为json并输出 */

    raw_fd_ostream linebbJson(OutDirectory + "/linebb" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream linebbJ(linebbJson);
    linebbJ.objectBegin();
    for (auto pss : linebbMap) {
      linebbJ.attributeBegin(pss.first);
      linebbJ.value(pss.second);
      linebbJ.attributeEnd();
    }
    linebbJ.objectEnd();

    /* 将maxLineMap转为json并输出 */

    raw_fd_ostream maxLineJson(OutDirectory + "/maxLine" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream maxLineJ(maxLineJson);
    maxLineJ.objectBegin();
    for (auto psi : maxLineMap) {
      maxLineJ.attributeBegin(psi.first);
      maxLineJ.value(psi.second);
      maxLineJ.attributeEnd();
    }
    maxLineJ.objectEnd();

    /* 将funcParamMap转换为json并输出 */

    raw_fd_ostream funcParamJson(OutDirectory + "/funcParam" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream funcParamJ(funcParamJson);
    funcParamJ.objectBegin();
    for (auto it = funcParamMap.begin(); it != funcParamMap.end(); it++) {
      funcParamJ.attributeBegin(it->first);
      funcParamJ.arrayBegin();
      for (auto param : it->second)
        funcParamJ.value(param);
      funcParamJ.arrayEnd();
      funcParamJ.attributeEnd();
    }
    funcParamJ.objectEnd();

    /* 将callArgsMap转换为json并输出 */

    raw_fd_ostream callArgsJson(OutDirectory + "/callArgs" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream callArgsJ(callArgsJson);
    callArgsJ.objectBegin();
    for (auto it = callArgsMap.begin(); it != callArgsMap.end(); it++) {
      callArgsJ.attributeBegin(it->first);
      callArgsJ.objectBegin();
      for (auto iit = it->second.begin(); iit != it->second.end(); iit++) {
        callArgsJ.attributeBegin(iit->first);
        callArgsJ.arrayBegin();
        for (auto args : iit->second) {
          callArgsJ.arrayBegin();
          for (auto arg : args) {
            callArgsJ.value(arg);
          }
          callArgsJ.arrayEnd();
        }
        callArgsJ.arrayEnd();
        callArgsJ.attributeEnd();
      }
      callArgsJ.objectEnd();
      callArgsJ.attributeEnd();
    }
    callArgsJ.objectEnd();

    /* 将bbFuncMap转换为json并输出 */

    raw_fd_ostream bbFuncJson(OutDirectory + "/bbFunc" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream bbFuncJ(bbFuncJson);
    bbFuncJ.objectBegin();
    for (auto it = bbFuncMap.begin(); it != bbFuncMap.end(); it++) { // 遍历map并转换为json, llvm的json似乎不会自动格式化?
      bbFuncJ.attributeBegin(it->first);
      bbFuncJ.value(it->second);
      bbFuncJ.attributeEnd();
    }
    bbFuncJ.objectEnd();

    /* CFG */

    for (auto &F : M) {

      bool has_BBs = false;
      std::string funcName = F.getName().str();

      /* Black list of function names */
      if (isBlacklisted(&F)) {
        continue;
      }

      for (auto &BB : F) {

        std::string bb_name("");
        std::string filename;
        unsigned line;

        for (auto &I : BB) {
          getDebugLoc(&I, filename, line);

          /* Don't worry about external libs */
          static const std::string Xlibs("/usr/");
          if (filename.empty() || line == 0 || !filename.compare(0, Xlibs.size(), Xlibs))
            continue;

          if (bb_name.empty()) {

            std::size_t found = filename.find_last_of("/\\");
            if (found != std::string::npos)
              filename = filename.substr(found + 1);

            bb_name = filename + ":" + std::to_string(line);
          }

          if (auto *c = dyn_cast<CallInst>(&I)) {

            std::size_t found = filename.find_last_of("/\\");
            if (found != std::string::npos)
              filename = filename.substr(found + 1);

            if (auto *CalledF = c->getCalledFunction()) {
              if (!isBlacklisted(CalledF))
                bbcalls << bb_name << "," << CalledF->getName().str() << "\n";
            }
          }
        }

        if (!bb_name.empty()) {

          BB.setName(bb_name + ":");
          if (!BB.hasName()) {
            std::string newname = bb_name + ":";
            Twine t(newname);
            SmallString<256> NameData;
            StringRef NameRef = t.toStringRef(NameData);
            MallocAllocator Allocator;
            BB.setValueName(ValueName::Create(NameRef, Allocator));
          }

          bbnames << BB.getName().str() << "\n";
          has_BBs = true;

        }
      }

      if (has_BBs) {

        /* Get entry BB */

        funcEntryMap[F.getName().str()] = F.getEntryBlock().getName().str();

        /* Print CFG */

        std::string cfgFileName = dotfiles + "/cfg." + funcName + ".dot";
        std::error_code EC;
        raw_fd_ostream cfgFile(cfgFileName, EC, sys::fs::F_None);
        if (!EC) {
          WriteGraph(cfgFile, &F, true);
        }

        fnames << F.getName().str() << "\n";
      }
    }

    /* 将funcEntryMap转换为json并输出 */

    raw_fd_ostream funcEntryJson(OutDirectory + "/funcEntry" + std::to_string(fileIdx) + ".json", EC, sys::fs::F_None);
    json::OStream funcEntryJ(funcEntryJson);
    funcEntryJ.objectBegin();
    for (auto it = funcEntryMap.begin(); it != funcEntryMap.end(); it++) { // 遍历map并转换为json, llvm的json似乎不会自动格式化?
      funcEntryJ.attributeBegin(it->first);
      funcEntryJ.value(it->second);
      funcEntryJ.attributeEnd();
    }
    funcEntryJ.objectEnd();

  } else {

    /* MyDist instrumentation mode */

    LLVMContext &C = M.getContext();

    IntegerType *Int8Ty  = IntegerType::getInt8Ty(C);
    IntegerType *Int32Ty = IntegerType::getInt32Ty(C);
    IntegerType *Int64Ty = IntegerType::getInt64Ty(C);

    /* x86_64 */

    IntegerType *LargestType = Int64Ty;
#if 0
    ConstantInt *MapCntLoc = ConstantInt::get(LargestType, MAP_SIZE + 8);
    ConstantInt *One = ConstantInt::get(LargestType, 1);
#endif

    ConstantInt *MapDistLoc = ConstantInt::get(LargestType, MAP_SIZE);

    /* Get globals for the SHM region and the previous location. Note that
      __afl_prev_loc is thread-local. */

    GlobalVariable *AFLMapPtr =
        new GlobalVariable(M, PointerType::get(Int8Ty, 0), false,
                          GlobalValue::ExternalLinkage, 0, "__afl_area_ptr");

    GlobalVariable *AFLPrevLoc = new GlobalVariable(
        M, Int32Ty, false, GlobalValue::ExternalLinkage, 0, "__afl_prev_loc",
        0, GlobalVariable::GeneralDynamicTLSModel, 0, false);

    /* Instrument all the things! */

    for (auto &F : M)
      for (auto &BB : F) {

        s64 mydist = -1;
        std::string bbname;

        for (auto &I : BB) {
          std::string filename;
          unsigned line;
          getDebugLoc(&I, filename, line);

          if (filename.empty() || line == 0)
            continue;
          std::size_t found = filename.find_last_of("/\\");
          if (found != std::string::npos)
            filename = filename.substr(found + 1);

          bbname = filename + ":" + std::to_string(line);
          break;
        }

        if (!bbname.empty() && bbset.count(bbname)) {

          for (auto&& psi : distMap) {

            if (bbname.compare(psi.first) == 0)
              mydist = psi.second;

          }

        }

        BasicBlock::iterator IP = BB.getFirstInsertionPt();
        IRBuilder<> IRB(&(*IP));

        if (AFL_R(100) >= inst_ratio) continue;

        /* Make up cur_loc */

        unsigned int cur_loc = AFL_R(MAP_SIZE);

        ConstantInt *CurLoc = ConstantInt::get(Int32Ty, cur_loc);

        /* Load prev_loc */

        LoadInst *PrevLoc = IRB.CreateLoad(AFLPrevLoc);
        PrevLoc->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));
        Value *PrevLocCasted = IRB.CreateZExt(PrevLoc, IRB.getInt32Ty());

        /* Load SHM pointer */

        LoadInst *MapPtr = IRB.CreateLoad(AFLMapPtr);
        MapPtr->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));
        Value *MapPtrIdx =
            IRB.CreateGEP(MapPtr, IRB.CreateXor(PrevLocCasted, CurLoc));

        /* Update bitmap */

        LoadInst *Counter = IRB.CreateLoad(MapPtrIdx);
        Counter->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));
        Value *Incr = IRB.CreateAdd(Counter, ConstantInt::get(Int8Ty, 1));
        IRB.CreateStore(Incr, MapPtrIdx)
            ->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));

        /* Set prev_loc to cur_loc >> 1 */

        StoreInst *Store =
            IRB.CreateStore(ConstantInt::get(Int32Ty, cur_loc >> 1), AFLPrevLoc);
        Store->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));

        if (mydist >= 0) {

          ConstantInt *MyDist =
              ConstantInt::get(LargestType, (u64) (1 << mydist));

          /* Add mydist to shm[MAPSIZE] */

          Value *MapDistPtr = IRB.CreateBitCast(
              IRB.CreateGEP(MapPtr, MapDistLoc), LargestType->getPointerTo());
          LoadInst *MapDist = IRB.CreateLoad(MapDistPtr);
          MapDist->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));

          Value *IncrDist = IRB.CreateOr(MapDist, MyDist);
          IRB.CreateStore(IncrDist, MapDistPtr)
              ->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));

#if 0
          /* Increase count at shm[MAPSIZE + 8] */

          Value *MapCntPtr = IRB.CreateBitCast(
              IRB.CreateGEP(MapPtr, MapCntLoc), LargestType->getPointerTo());
          LoadInst *MapCnt = IRB.CreateLoad(MapCntPtr);
          MapCnt->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));

          Value *IncrCnt = IRB.CreateAdd(MapCnt, One);
          IRB.CreateStore(IncrCnt, MapCntPtr)
              ->setMetadata(M.getMDKindID("nosanitize"), MDNode::get(C, None));
#endif

        }

#ifdef CHECK_COV
        /* TEMP: 根据覆盖的changeBB的不同对shm进行修改, 目前最多查看32个changeBB的覆盖情况 */

        int idx = find(changes.begin(), changes.end(), bbname) - changes.begin();

        if (idx < changes.size() && idx < 32) {

          ConstantInt *MapCovLoc = ConstantInt::get(LargestType, MAP_SIZE + 16 + idx);

          Value *MapMarkPtr = IRB.CreateBitCast(
            IRB.CreateGEP(MapPtr,MapCovLoc), Int8Ty->getPointerTo());
          IRB.CreateStore(ConstantInt::get(Int8Ty, 65), MapMarkPtr)
              ->setMetadata(M.getMDKindID("nonsanitize"), MDNode::get(C, None));

        }
#endif

        inst_blocks++;

      }

  }

  /* Say something nice. */

  if (!is_preprocessing && !be_quiet) {

    if (!inst_blocks) WARNF("No instrumentation targets found.");
    else OKF("Instrumented %u locations (%s mode, ratio %u%%).",
             inst_blocks, getenv("AFL_HARDEN") ? "hardened" :
             ((getenv("AFL_USE_ASAN") || getenv("AFL_USE_MSAN")) ?
              "ASAN/MSAN" : "non-hardened"), inst_ratio);

  }

  return true;

}


static void registerAFLPass(const PassManagerBuilder &,
                            legacy::PassManagerBase &PM) {

  PM.add(new AFLCoverage());

}


static RegisterStandardPasses RegisterAFLPass(
    PassManagerBuilder::EP_ModuleOptimizerEarly, registerAFLPass);

static RegisterStandardPasses RegisterAFLPass0(
    PassManagerBuilder::EP_EnabledOnOptLevel0, registerAFLPass);
