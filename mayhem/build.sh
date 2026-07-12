#!/usr/bin/env bash
#
# mayhem/build.sh — build the ucc162.3 fuzz target and the functional test suites.
#
# The repo bundles three educational compilers: myc/ (a simplified-C compiler + bytecode
# interpreter), ucc/ (a full C89 compiler emitting 32-bit x86 asm) and sc2/ (book-chapter
# demo code). The historical Mayhem target is `myc`: a file-input CLI (`myc <src.c>`) that
# lexes/parses/compiles the input and interprets it on a virtual machine — so we build it
# two ways:
#   build/myc         sanitized + DWARF-3  -> the Mayhem target (file-input, `myc @@`)
#   build-oracle/myc  normal flags         -> mayhem/test.sh's known-answer oracle
# We also build ucc/ exactly as upstream documents (make + make install), because upstream's
# functional test suite (`make -C ucc test`, the ucl self-hosting bootstrap comparison) runs
# against that build in mayhem/test.sh. ucc's Makefiles hardcode gcc -m32, so the Dockerfile
# installs gcc-multilib/g++-multilib. No network access needed here; no upstream files edited.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the environment (base image exports the defaults); fall back for a bare run.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

MYC_SRCS=(myc/src/*.cpp)
# -w -fpermissive: 2007-era C++ (char* string literals, K&R-isms) that clang-19 otherwise
# rejects; upstream builds it with `g++ -Wno-write-strings`.

# 1) Sanitized fuzz target — the PROJECT ITSELF is instrumented (not just a wrapper), so
#    ASan/UBSan see bugs inside the lexer/parser/VM. -O1 keeps frames readable for triage;
#    $DEBUG_FLAGS after the sanitizer flags so -gdwarf-3 wins (DWARF must be < 4).
mkdir -p build
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -w -fpermissive "${MYC_SRCS[@]}" -o build/myc

# 2) Clean oracle build (NO sanitizers) so mayhem/test.sh is an honest functional oracle that
#    won't false-fail on benign UB. $COVERAGE_FLAGS is empty by default (a coverage build
#    appends it here).
mkdir -p build-oracle
# shellcheck disable=SC2086
$CXX -O2 -w -fpermissive $COVERAGE_FLAGS "${MYC_SRCS[@]}" -o build-oracle/myc

# 3) Upstream's own functional test suite build: ucc, exactly as the README documents
#    (make; make install -> ucc/bin). mayhem/test.sh then RUNS `make -C ucc test` (the ucl
#    self-hosting bootstrap: compile ucl with ucc twice, strip, byte-compare). Normal flags —
#    ucc's Makefiles hardcode gcc -m32.
make -C ucc -j"$MAYHEM_JOBS"
make -C ucc install

echo "build.sh: built build/myc (sanitized target), build-oracle/myc (oracle), ucc/bin (upstream test suite)"
