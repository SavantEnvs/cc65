#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for the cc65 command-line tools.
#
# Runs the CLEAN (non-sanitized, dynamically linked) tools built by
# mayhem/build.sh (/mayhem/<tool>_clean) on FIXED inputs and asserts the EXACT
# values they compute — the 6502 machine-code bytes ca65 emits (read from its own
# -l listing), the raw bytes ld65 links them into, the mnemonics da65 recovers
# from that binary, the instructions cc65 generates for a fixed C function, and
# the object-file magic od65 dumps. Every one is a known-answer assertion through
# a real, LD_PRELOAD-reachable binary: a PATCH that neuters a tool to a no-op
# (or verify-repo's sabotage shim that _exit(0)s it) produces no listing/binary/
# text, so the assertions FAIL. Exit-code-only / marker oracles are forbidden
# (docs/netnew-worker-prompt.md §4); this asserts computed values.
#
# Emits a CTRF summary + a compact `CTRF {...}` stdout marker; exits non-zero
# iff failed>0. Probes are unconditional: a missing binary is a FAILURE.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

CA65=/mayhem/ca65_clean
CC65=/mayhem/cc65_clean
DA65=/mayhem/da65_clean
LD65=/mayhem/ld65_clean
OD65=/mayhem/od65_clean

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc65-kat.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0
failed=0
ok()   { echo "PASS  $1"; passed=$((passed + 1)); }
bad()  { echo "FAIL  $1"; failed=$((failed + 1)); }

# Fail loudly if build.sh did not produce an oracle binary (a build bug, not a skip).
for b in "$CA65" "$CC65" "$DA65" "$LD65" "$OD65"; do
  if [ ! -x "$b" ]; then
    echo "FATAL: $b missing/not executable — mayhem/build.sh did not build the oracle" >&2
    emit_ctrf "cc65-cli-kat" 0 1 0
    exit 1
  fi
done

# Squeeze all whitespace runs to one space so assertions are layout-independent.
squeeze() { tr -s '[:space:]' ' '; }
# assert_contains <label> <haystack-string> <needle>
assert_contains() {
  local label="$1" hay="$2" want="$3"
  if printf '%s' "$hay" | grep -qF -- "$want"; then ok "$label -> found '$want'"
  else bad "$label : expected '$want' not found"; fi
}

# ---------------------------------------------------------------------------
# 1) ca65: assemble a fixed 6502 source; the -l listing must show the exact
#    opcode bytes:  lda #$01 -> A9 01 | sta $0200 -> 8D 00 02 | ldx #$00 -> A2 00
#                   inx -> E8 | rts -> 60
# ---------------------------------------------------------------------------
ASM="$WORK/in.s"; LST="$WORK/in.lst"; OBJ="$WORK/in.o"
printf '\tlda #$01\n\tsta $0200\n\tldx #$00\n\tinx\n\trts\n' > "$ASM"
"$CA65" -g -l "$LST" -o "$OBJ" "$ASM" >/dev/null 2>&1 || true
BYTES=""
if [ -f "$LST" ]; then
  # Per listing line: address column, then the emitted bytes, then the source
  # (after a tab). Keep only the 2-hex-digit code-column tokens.
  BYTES="$(sed -E 's/\t.*$//' "$LST" | grep -oE '\b[0-9A-Fa-f]{2}\b' | tr '[:lower:]' '[:upper:]' | tr '\n' ' ')"
fi
echo "ca65 listing code bytes: [$BYTES]"
assert_contains "ca65 lda_imm"  " $BYTES " " A9 01 "
assert_contains "ca65 sta_abs"  " $BYTES " " 8D 00 02 "
assert_contains "ca65 ldx_imm"  " $BYTES " " A2 00 "
assert_contains "ca65 inx_rts"  " $BYTES " " E8 60 "

# ---------------------------------------------------------------------------
# 2) ld65: link that object with the built-in `none` target (raw binary, no
#    header) — the output file must be EXACTLY the 9 code bytes.
# ---------------------------------------------------------------------------
BIN="$WORK/in.bin"
"$LD65" -t none -o "$BIN" "$OBJ" >/dev/null 2>&1 || true
LINKED=""
[ -f "$BIN" ] && LINKED="$(od -An -v -tx1 "$BIN" | squeeze | sed -E 's/^ //; s/ $//')"
echo "ld65 linked bytes: [$LINKED]"
if [ "$LINKED" = "a9 01 8d 00 02 a2 00 e8 60" ]; then ok "ld65 raw binary == a9 01 8d 00 02 a2 00 e8 60"
else bad "ld65 raw binary: got [$LINKED], want [a9 01 8d 00 02 a2 00 e8 60]"; fi

# ---------------------------------------------------------------------------
# 3) da65: disassemble the linked binary — the original mnemonics/operands must
#    come back.
# ---------------------------------------------------------------------------
DIS="$WORK/in.dis"
"$DA65" -o "$DIS" "$BIN" >/dev/null 2>&1 || true
DTXT=""
[ -f "$DIS" ] && DTXT="$(grep -vE '^[[:space:]]*;' "$DIS" | squeeze)"
echo "da65 text: [$(printf '%s' "$DTXT" | cut -c1-120)]"
assert_contains "da65 lda"  "$DTXT" "lda #\$01"
assert_contains "da65 sta"  "$DTXT" "sta \$0200"
assert_contains "da65 ldx"  "$DTXT" "ldx #\$00"
assert_contains "da65 inx"  "$DTXT" " inx "
assert_contains "da65 rts"  "$DTXT" " rts"

# ---------------------------------------------------------------------------
# 4) od65: dump the object header — the cc65 object magic (0x616E7A55 = "Uzna")
#    must be reported, and the file must carry debug info (we assembled with -g).
# ---------------------------------------------------------------------------
OTXT="$("$OD65" -H "$OBJ" 2>/dev/null | squeeze || true)"
echo "od65 header: [$(printf '%s' "$OTXT" | cut -c1-120)]"
assert_contains "od65 magic"   "$OTXT" "Magic: 0x616E7A55"
assert_contains "od65 dbgflag" "$OTXT" "OBJ_FLAGS_DBGINFO"

# ---------------------------------------------------------------------------
# 5) cc65: compile a fixed C function — the generated assembler must load the
#    constant 42 (lda #$2A), clear X for the 16-bit return (ldx #$00), export
#    the C symbol (_f) and end the proc with rts.
# ---------------------------------------------------------------------------
CSRC="$WORK/kat.c"; CASM="$WORK/kat.s"
printf 'unsigned char f(void){return 42;}\n' > "$CSRC"
"$CC65" -o "$CASM" "$CSRC" >/dev/null 2>&1 || true
CTXT=""
[ -f "$CASM" ] && CTXT="$(grep -vE '^[[:space:]]*;' "$CASM" | squeeze)"
echo "cc65 asm: [$(printf '%s' "$CTXT" | cut -c1-160)]"
assert_contains "cc65 lda_42"   "$CTXT" "lda #\$2A"
assert_contains "cc65 ldx_0"    "$CTXT" "ldx #\$00"
assert_contains "cc65 export_f" "$CTXT" ".export _f"
assert_contains "cc65 proc_f"   "$CTXT" ".proc _f: near"
assert_contains "cc65 rts"      "$CTXT" "rts .endproc"

emit_ctrf "cc65-cli-kat" "$passed" "$failed" 0
