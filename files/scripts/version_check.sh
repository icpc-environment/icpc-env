#!/bin/bash

VFILE="/tmp/versions.txt"
echo "Software Versions" > $VFILE

# these checks happen outside the chroot
echo -e "==== javac Version ====" | tee -a $VFILE
javac -version 2>&1 | tee -a $VFILE

echo -e "\n\n==== GCC Version ====" | tee -a $VFILE
gcc --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== G++ Version ====" | tee -a $VFILE
g++ --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== FPC(Pascal) Version ====" | tee -a $VFILE
fpc -version 2>&1 | tee -a $VFILE

echo -e "\n\n==== Haskell Version ====" | tee -a $VFILE
ghc --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== gmcs(mono compiler) Version ====" | tee -a $VFILE
gmcs --version 2>&1 | tee -a $VFILE

# There is currently no compiler setup for fortran
echo -e "\n\n==== gfortran Version ====" | tee -a $VFILE
gfortran --version 2>&1 | tee -a $VFILE

# There is currently no compiler set up for ada
echo -e "\n\n==== GNAT(ADA) Version ====" | tee -a $VFILE
gnat 2>&1 | head -n1 | tee -a $VFILE

# This needs to be checked in the chroot
echo -e "\n\n==== Python Version ====" | tee -a $VFILE
python --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== Java Version ====" | tee -a $VFILE
java -version 2>&1 | tee -a $VFILE

echo -e "\n\n==== Mono Version ====" | tee -a $VFILE
mono --version  2>&1 | tee -a $VFILE

echo -e "\n\n==== Scala Version ====" | tee -a $VFILE
scala -version 2>&1 | tee -a $VFILE

echo -e "\n\n==== Kotlin Version ====" | tee -a $VFILE
kotlin -version 2>&1 | tee -a $VFILE

echo -e "\n\n==== Rust Version ====" | tee -a $VFILE
rustc --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== NodeJS Version ====" | tee -a $VFILE
node --version 2>&1 | tee -a $VFILE

echo -e "\n\n==== OCaml Version ====" | tee -a $VFILE
ocaml --version 2>&1 | tee -a $VFILE

echo -e "Software versions written to: $VFILE\n\n"
