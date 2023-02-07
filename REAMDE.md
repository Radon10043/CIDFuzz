# CIDFuzz: Fuzz Testing for Continuous Integration

CIDFuzz is built based on [AFL](https://lcamtuf.coredump.cx/afl/), it can be applied to automated testing during continuous integration.

The specific process is as follows:

* First, differential analysis is performed to determine the change points generated during continuous integration, the change points are added to the taint source set, and the static analysis is conducted to calculate the distances between each basic block and the taint sources.

* Then, the project under test is instrumented according to the distances. During fuzz testing, Testing resources are allocated based on the coverage of seeds to test the change points effectively.

# How to perform fuzzing with CIDFuzz

1. Download and install deps

```shell
cd /path/to/CIDFuzz/scripts/build
sudo ./cidfuzz-build.sh
```

2. Compile CIDFuzz and LLVM-instrumentation pass

```shell
cd /path/to/CIDFuzz
make clean all  # If "clean" is not required, you can also execute "make" or "make all"
cd llvm_mode
make clean all  # If "clean" is not required, you can also execute "make" or "make all"
```

3. Run the fuzzing script of project under test (e.g. [libming](https://www.github.com/libming/libming)). The meaning of each parameter of the fuzzing script is as follows:
   * $1: fuzzer
   * $2: repeat times

```
cd /path/to/CIDFuzz/scripts/fuzz/libming/CVE-2020-6628
./libming-fuzz.sh CIDFuzz 5
```

4. For project binutils, we follow experiments settings in original paper of AFLGo and its [fuzzing script](https://github.com/aflgo/aflgo/blob/master/scripts/fuzz/cxxfilt-CVE-2016-4487.sh). The meaning of each parameter of binutils' fuzzing script is as follows:
   * $1: fuzzer
   * $2: repeat times
   * $3: CVE-ID (Specially, if you set $3 to CVE-2016-4488, script will patch CVE-2016-4487 first)

```
cd /path/to/CIDFuzz/scripts/fuzz/binutils
./binutils-fuzz.sh CIDFuzz 20 CVE-2016-4487
```