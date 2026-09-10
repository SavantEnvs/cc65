// mayhem/lsan_off.cc — build-time LeakSanitizer off-switch (fleet policy).
//
// -fsanitize=address always bundles LeakSanitizer in; the cc65 tools are classic
// CLI programs that exit() without freeing (by design), so every run would end in
// a leak report that drowns the memory-corruption findings we fuzz for. Defining
// this hook turns leak checking off at link time while ASan + UBSan stay fully
// active and halting. mayhem/build.sh compiles this TU with $SANITIZER_FLAGS and
// links the object into every sanitized fuzz binary. No runtime knobs, no
// options overrides — this is the only sanctioned mechanism.
extern "C" int __lsan_is_turned_off(void) { return 1; }
