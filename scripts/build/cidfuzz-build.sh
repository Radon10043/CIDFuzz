#!/bin/bash
set -e # exit on error

# Install deps
add-apt-repository -y ppa:ubuntu-toolchain-r/test
DEP_PACKAGES="build-essential make ninja-build git binutils-gold binutils-dev curl wget g++-10 jq python3.8"
apt-get install -y $DEP_PACKAGES

# gcc-10 and g++-10 have high priority
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 1
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 2
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 1
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 2

# python3.8 has high priority
update-alternatives --install /usr/bin/python python /usr/bin/python2.7 1
update-alternatives --install /usr/bin/python python /usr/bin/python3.8 2

UBUNTU_VERSION=`cat /etc/os-release | grep VERSION_ID | cut -d= -f 2`
UBUNTU_YEAR=`echo $UBUNTU_VERSION | cut -d. -f 1`
UBUNTU_MONTH=`echo $UBUNTU_VERSION | cut -d. -f 2`

if [[ "$UBUNTU_YEAR" > "16" || "$UBUNTU_MONTH" > "04" ]]
then
    apt-get install -y python3-distutils
fi

export CXX=g++
export CC=gcc
unset CFLAGS
unset CXXFLAGS

mkdir ~/build; cd ~/build

# build cmake-3.13.4
wget https://github.com/Kitware/CMake/releases/download/v3.13.4/cmake-3.13.4.tar.gz
tar zxvf cmake-3.13.4.tar.gz
cd cmake-3.13.4
./bootstrap
make
make install
cd ..

# build LLVM & clang
mkdir llvm_tools; cd llvm_tools
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/llvm-11.0.0.src.tar.xz
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/clang-11.0.0.src.tar.xz
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/compiler-rt-11.0.0.src.tar.xz
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/libcxx-11.0.0.src.tar.xz
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/libcxxabi-11.0.0.src.tar.xz
tar xf llvm-11.0.0.src.tar.xz
tar xf clang-11.0.0.src.tar.xz
tar xf compiler-rt-11.0.0.src.tar.xz
tar xf libcxx-11.0.0.src.tar.xz
tar xf libcxxabi-11.0.0.src.tar.xz
mv clang-11.0.0.src ~/build/llvm_tools/llvm-11.0.0.src/tools/clang
mv compiler-rt-11.0.0.src ~/build/llvm_tools/llvm-11.0.0.src/projects/compiler-rt
mv libcxx-11.0.0.src ~/build/llvm_tools/llvm-11.0.0.src/projects/libcxx
mv libcxxabi-11.0.0.src ~/build/llvm_tools/llvm-11.0.0.src/projects/libcxxabi

mkdir -p build-llvm/llvm; cd build-llvm/llvm
cmake -G "Ninja" \
      -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="X86" \
      -DLLVM_BINUTILS_INCDIR=/usr/include ~/build/llvm_tools/llvm-11.0.0.src
ninja; ninja install

cd ~/build/llvm_tools
mkdir -p build-llvm/msan; cd build-llvm/msan
cmake -G "Ninja" \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DLLVM_USE_SANITIZER=Memory -DCMAKE_INSTALL_PREFIX=/usr/msan/ \
      -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="X86" \
      ~/build/llvm_tools/llvm-11.0.0.src
ninja cxx; ninja install-cxx

# Install LLVMgold in bfd-plugins
mkdir -p /usr/lib/bfd-plugins
cp /usr/local/lib/libLTO.so /usr/lib/bfd-plugins
cp /usr/local/lib/LLVMgold.so /usr/lib/bfd-plugins

# install some packages
export LC_ALL=C
apt-get update
apt install -y python-dev python3 python3-dev python3-pip autoconf automake libtool-bin python-bs4 libboost-all-dev # libclang-11.0-dev
python -m pip install --upgrade pip
python -m pip install networkx pydot pydotplus
