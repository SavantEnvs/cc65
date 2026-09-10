#!/usr/bin/env bash
#
# mayhem/build.sh — build the cc65 command-line tools as RAW (process-per-input)
# Mayhem targets, plus a separate clean build that mayhem/test.sh uses as the
# behavioral oracle. Purely additive: upstream src/ is compiled verbatim (the
# sanitized build runs in a shadow copy under mayhem/build/ so it never touches
# the upstream tree or the oracle build).
#
# cc65's public interface is its CLI tools (reviewer standard, PR #780), so each
# tool is fuzzed exactly as shipped — one process per input, fed one file via a
# bare `@@`, no in-process harness, no filesystem tricks:
#
#   /mayhem/ca65      6502 macro assembler        <- assembler source (text)
#   /mayhem/cc65      C compiler (-Osir)          <- C source (text; /mayhem/include on the path)
#   /mayhem/da65      disassembler                <- raw 6502 binary   [target da65]
#                                                 <- info file (text)  [target da65-info]
#   /mayhem/ld65      linker (-t none)            <- ca65/cc65 object  [target ld65]
#                     linker (-C <cfg>)           <- linker config     [target ld65-cfg]
#   /mayhem/od65      object-file dumper          <- ca65/cc65 object
#   /mayhem/co65      o65 -> assembler converter  <- o65 binary
#   /mayhem/sp65      sprite/bitmap converter     <- PCX image
#   /mayhem/ar65      archiver (`t` = list)       <- ar65 library
#   /mayhem/grc65     GEOS resource compiler      <- .grc source (text)
#   /mayhem/chrcvt65  BGI vector-font converter   <- Borland .chr font
#
# Deliberately NOT fuzzed:
#   cl65   a driver that only exec()s the tools above (no parsing of its own);
#   sim65  a 6502 emulator whose GUEST program drives host file I/O through the
#          paravirt hooks (PVOpen/PVWrite/PVRead: the fuzzed program chooses the
#          host paths). It is not a file-format parser and running arbitrary
#          guest code with host I/O blind is not a sane raw target.
#
# Sanitized fuzz build: every tool is compiled with $SANITIZER_FLAGS (base ENV:
# ASan+UBSan, both halting) AND -fsanitize=fuzzer-no-link UNCONDITIONALLY so the
# fuzzed code carries SanCov edge instrumentation (otherwise Mayhem records
# 0 edges), plus $DEBUG_FLAGS (-g -gdwarf-3: DWARF<4 for Mayhem triage). The
# build-time LSan off-switch mayhem/lsan_off.cc is linked into every one of them.
#
# Two UBSan checks are relaxed — and ONLY these two — because upstream's common/
# string/collection helpers hit them on essentially every input, which made the
# sanitized ca65 abort on a 1-byte file (the cloud run #2 SIGABRT) and would
# starve every target of coverage:
#   nonnull-attribute   common/strbuf.c:144  memcpy(dst, NULL, 0) when a StrBuf
#                       that was never allocated (Buf == NULL, Len == 0) grows.
#   pointer-overflow    common/coll.c:386    Dest->Items + Dest->Count with
#                       Items == NULL, Count == 0 (the `NULL + 0` idiom).
# Both are the classic benign zero-length idioms; ASan and every other UBSan
# check stay on and halting.
#
# Oracle build: a SEPARATE clean `make -C src` with the project's normal flags
# (no sanitizer, no DWARF override) -> /mayhem/<tool>_clean. Dynamically linked
# so mayhem/test.sh's known-answer assertions (and verify-repo's LD_PRELOAD
# sabotage shim) actually reach the program.
#
# Both builds compile in the in-image data directories (asminc/, include/, cfg/)
# in place of the packaging default ($PREFIX/share/cc65): cc65 then resolves
# `#include <stdio.h>`, ld65 finds `-t none`'s none.cfg and ca65 finds .include
# files from the read-only image, so seeds lifted from upstream's test suite
# exercise the full pipeline instead of dying on a missing header.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# The org base image sets SANITIZER_FLAGS as an ENV; this default only fires for
# a bare local run. `=` (not `:=`) so an explicit empty value (no-sanitizer
# build) is kept.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries the DWARF<4 contract (§6.2 item 10); clang-19's plain -g
# emits DWARF-5, so be explicit.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
SRC="${SRC:-/mayhem}"
cd "$SRC"

# The relaxed UBSan checks (see header). Appended AFTER the sanitizer set so it
# wins; harmless when SANITIZER_FLAGS is empty.
FUZZ_SAN_FLAGS="$SANITIZER_FLAGS -fno-sanitize=nonnull-attribute,pointer-overflow"

# In-image data dirs compiled into the tools (see header). lib/ and target/ are
# not built (the 6502 runtime libraries are not needed for any target).
DATA_VARS=(
  "CA65_INC=$SRC/asminc"
  "CC65_INC=$SRC/include"
  "LD65_CFG=$SRC/cfg"
  "LD65_LIB=$SRC/lib"
  "LD65_OBJ=$SRC/lib"
  "CL65_TGT=$SRC/target"
)

TOOLS="ca65 cc65 da65 ld65 od65 co65 sp65 ar65 grc65 chrcvt65"

echo "== build.sh: CC=$CC SANITIZER_FLAGS=[$SANITIZER_FLAGS] jobs=$MAYHEM_JOBS =="

# ---------------------------------------------------------------------------
# 1) Sanitized fuzz build in a shadow copy of src/ -> mayhem/build/{wrk,bin}.
#    src/Makefile writes to ../wrk and ../bin relative to itself, so copying src/
#    to mayhem/build/src keeps the sanitized objects apart from the oracle build
#    (no make clean / stash dance, and re-runs are idempotent).
#    USER_CFLAGS is appended by src/Makefile into its own CFLAGS (which keeps
#    -O3 -I common -Wall ...); CC must be on the command line because the
#    Makefile hard-assigns CC=gcc; LDLIBS is set on the command line (a
#    command-line variable overrides the Makefile's `LDLIBS += -lm`), so -lm is
#    repeated here alongside the LSan hook object.
# ---------------------------------------------------------------------------
rm -rf mayhem/build
mkdir -p mayhem/build
cp -a src mayhem/build/src

"$CXX" $FUZZ_SAN_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o mayhem/build/lsan_off.o

make -C mayhem/build/src -j"$MAYHEM_JOBS" CC="$CC" \
     USER_CFLAGS="$FUZZ_SAN_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
     LDFLAGS="$FUZZ_SAN_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
     LDLIBS="$SRC/mayhem/build/lsan_off.o -lm" \
     "${DATA_VARS[@]}" \
     $TOOLS

for t in $TOOLS; do
  cp "mayhem/build/bin/$t" "/mayhem/$t"
  test -x "/mayhem/$t"
done
echo "== fuzz binaries built: $TOOLS =="

# ---------------------------------------------------------------------------
# 2) Oracle — clean build of the same tools with the project's normal flags
#    (no sanitizer, no DWARF override) -> /mayhem/<tool>_clean, via the
#    upstream Makefile in place (src/ -> wrk/, bin/).
# ---------------------------------------------------------------------------
make -C src -j"$MAYHEM_JOBS" CC="$CC" "${DATA_VARS[@]}" $TOOLS

for t in $TOOLS; do
  cp "bin/$t" "/mayhem/${t}_clean"
  test -x "/mayhem/${t}_clean"
  if ! file "/mayhem/${t}_clean" | grep -q 'dynamically linked'; then
    echo "FATAL: /mayhem/${t}_clean is not dynamically linked — the oracle would be un-neuterable" >&2
    file "/mayhem/${t}_clean" >&2
    exit 1
  fi
done

echo "== build.sh: OK =="
ls -l /mayhem/*65 /mayhem/*65_clean
