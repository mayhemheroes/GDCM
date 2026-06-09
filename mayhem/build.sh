#!/usr/bin/env bash
# gdcm/mayhem/build.sh — build GDCM (library + applications) with $SANITIZER_FLAGS so the fuzzed
# DICOM-parsing code is instrumented, then link the StrCaseCmp libFuzzer harness (and its standalone
# reproducer). Two Mayhem targets:
#   * strcasecmp  — libFuzzer harness (mayhem/fuzz_StrCaseCmp.cpp → gdcm::System::StrCaseCmp)
#   * gdcmpap3    — GDCM's own PAPYRUS 3.0 command-line tool (file-input DICOM parser), installed
#                   sanitized to /mayhem/install/bin/gdcmpap3.
#
# GDCM is a large CMake project that vendors all its deps (zlib/expat/openjpeg/charls/openssl/...),
# so this needs no system -dev packages. We do ONE sanitized build of just what the two targets
# need: the libraries + the applications (gdcmpap3). GDCM builds static libs by default
# (BUILD_SHARED_LIBS=OFF), which we link into the harness with --start-group to resolve cycles.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV (overridable). SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty
# value (--build-arg SANITIZER_FLAGS=) is honored → a no-sanitizer (natural-crash) build.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
# DEBUG_FLAGS: DWARF ≤ 3 required — clang-19 defaults to DWARF-5 with plain -g (§6.2 item 10).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

BUILD="$SRC/build"
INSTALL="$SRC/install"

# Idempotent re-runs: remove stale build trees so cmake always starts fresh. The source tree
# is read-only-during-coverage but build dirs are ours; clearing them avoids permission errors
# from stale .a files the installer previously locked down (openjp2, charls, etc.).
BUILD_TESTS="$SRC/build-tests"
rm -rf "$BUILD" "$INSTALL" "$BUILD_TESTS"

# 1) Configure + build GDCM (libraries + applications) WITH $SANITIZER_FLAGS so the fuzzed code is
#    instrumented. Static libs (default) → easy to link into the harness. Tests/examples off (heavy,
#    need the external test-data submodule). Vendored deps (USE_SYSTEM_* all default OFF).
cmake -S "$SRC" -B "$BUILD" \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DGDCM_BUILD_SHARED_LIBS=OFF \
      -DGDCM_BUILD_APPLICATIONS=ON \
      -DGDCM_BUILD_TESTING=OFF \
      -DGDCM_BUILD_EXAMPLES=OFF \
      -DGDCM_BUILD_DOCBOOK_MANPAGES=OFF \
      -DCMAKE_INSTALL_PREFIX="$INSTALL"
cmake --build "$BUILD" -j"$MAYHEM_JOBS"
cmake --install "$BUILD"

# gdcmpap3 (the file-input Mayhem target) is now at $INSTALL/bin/gdcmpap3, sanitized.
test -x "$INSTALL/bin/gdcmpap3"

# 2) Build the StrCaseCmp harness. gdcm::System::StrCaseCmp lives in gdcmCommon; link the full set of
#    installed static libs in a group so static link order / cycles resolve. Include dir is
#    install/include/gdcm-<maj.min> (version-derived) — glob it rather than hard-code.
GDCM_INC="$(echo "$INSTALL"/include/gdcm-*)"
GDCM_LIBS=( "$INSTALL"/lib/libgdcm*.a )

# 2a) libFuzzer binary (the Mayhem target).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I"$GDCM_INC" \
     "$SRC/mayhem/fuzz_StrCaseCmp.cpp" $LIB_FUZZING_ENGINE \
     -Wl,--start-group "${GDCM_LIBS[@]}" -Wl,--end-group \
     -o /mayhem/fuzz_StrCaseCmp

# 2b) Standalone (non-fuzzer) reproducer: same harness + LLVM's run-once driver instead of the engine.
#     Compile the C driver with $CC first so its LLVMFuzzerTestOneInput ref keeps C linkage (clang++
#     would mangle it and miss the harness's extern "C" definition). Respects $SANITIZER_FLAGS.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I"$GDCM_INC" \
     "$SRC/mayhem/fuzz_StrCaseCmp.cpp" /tmp/standalone_main.o \
     -Wl,--start-group "${GDCM_LIBS[@]}" -Wl,--end-group \
     -o /mayhem/fuzz_StrCaseCmp-standalone

echo "build.sh: built /mayhem/fuzz_StrCaseCmp (+ -standalone) and $INSTALL/bin/gdcmpap3"

# 3) Functional-test oracle (for test.sh / PATCH grading). GDCM's CTest suite mostly needs the
#    external `gdcmData` corpus (the Testing/Data git submodule, intentionally left UNINITIALIZED
#    here — no network fetch, no multi-GB corpus baked in). With GDCM_DATA_ROOT unfound, the
#    Common/Cxx driver (gdcmCommonTests) still builds + runs 22 SELF-CONTAINED unit tests
#    (Base64/ByteSwap/Swapper/String/System/Version/…); only its 3-4 data-dependent tests are
#    gated out (Testing/Source/Common/Cxx/CMakeLists.txt `if(GDCM_DATA_ROOT)`). We build just that
#    one test driver, in a SEPARATE build dir with the project's NORMAL flags (no sanitizers), so
#    it stays an honest PATCH oracle. test.sh only RUNS it. (When GDCM_DATA_ROOT is unfound the
#    configure step prints a benign advisory, not a fatal error.)
cmake -S "$SRC" -B "$BUILD_TESTS" \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DGDCM_BUILD_SHARED_LIBS=OFF \
      -DGDCM_BUILD_APPLICATIONS=OFF \
      -DGDCM_BUILD_TESTING=ON \
      -DGDCM_BUILD_EXAMPLES=OFF \
      -DGDCM_BUILD_DOCBOOK_MANPAGES=OFF
# Build ONLY the Common self-contained test driver (not the data-dependent drivers in the other
# Testing/ subdirs, which we never compile).
cmake --build "$BUILD_TESTS" --target gdcmCommonTests -j"$MAYHEM_JOBS"
test -x "$BUILD_TESTS/bin/gdcmCommonTests"

echo "build.sh: built $BUILD_TESTS/bin/gdcmCommonTests (self-contained Common unit tests)"
