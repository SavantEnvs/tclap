#!/usr/bin/env bash
# Builds, inside /mayhem: (1) the sanitized libFuzzer + standalone binary for each fuzz/fuzz_*.cpp
# harness (TCLAP is header-only, so the library is compiled into each harness TU), and (2) the
# project's own test suite with its normal flags in build/oracle for mayhem/test.sh.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export CC CXX

cd "$SRC"
OUT=/mayhem
TARGETS="fuzz_cmdline fuzz_stdoutput fuzz_value_traits"

# 1) Generate TCLAPConfig.h (configure only; nothing is compiled here).
rm -rf build/config
cmake -S . -B build/config -DCMAKE_CXX_COMPILER="$CXX" -DBUILD_DOC=OFF -DBUILD_EXAMPLES=OFF \
      -DBUILD_TESTING=OFF -DBUILD_FUZZ_REGRESSION=OFF -DBUILD_FUZZERS=OFF >/dev/null
CONFIG_INC="$SRC/build/config"

# 2) Fuzzer + standalone binary per harness. Harnesses are C++98 and the library is instrumented
#    (fuzzer-no-link) because it is compiled into the same TU.
mkdir -p build/obj
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o build/obj/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/obj/standalone_main.o
for t in $TARGETS; do
  common="-std=c++98 -O1 -DHAVE_TCLAP_CONFIG_H -I$SRC/include -I$CONFIG_INC $SRC/fuzz/$t.cpp"
  $CXX $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS $common $LIB_FUZZING_ENGINE \
       build/obj/lsan_off.o -o "$OUT/$t"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $common build/obj/standalone_main.o \
       build/obj/lsan_off.o -o "$OUT/$t-standalone"
done

# 3) The upstream test suite (unit tests + example-output tests) with NORMAL flags: no sanitizers,
#    no DWARF override.
rm -rf build/oracle
cmake -S . -B build/oracle -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" -DBUILD_DOC=OFF -DBUILD_EXAMPLES=ON -DBUILD_TESTING=ON \
      -DBUILD_UNITTESTS=ON -DBUILD_FUZZ_REGRESSION=OFF -DBUILD_FUZZERS=OFF >/dev/null
cmake --build build/oracle -j"$MAYHEM_JOBS"
