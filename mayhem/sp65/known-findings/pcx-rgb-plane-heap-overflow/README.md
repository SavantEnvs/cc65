# sp65: heap-buffer-overflow WRITE for every 24/32-bit (3- or 4-plane) PCX image

- **Target:** `sp65` — `/mayhem/sp65 -r in.pcx -c raw -w out.bin`
- **Reproducer:** `rgb24.pcx` (188 bytes; a spec-valid 4x4 PCX, 8 bpp x 3 planes, RLE, palette-info 1).
  Kept OUT of `mayhem/sp65/testsuite/` on purpose: a crashing seed would be replayed on every run.
- **Report:** `asan-report.txt` — `AddressSanitizer: heap-buffer-overflow WRITE of size 1 ...
  src/sp65/pcx.c:487:25 in ReadPCXFile`, 0 bytes past the 124-byte bitmap allocated by `NewBitmap`.
- **Reproduce:** `cp rgb24.pcx in.pcx && /mayhem/sp65 -r in.pcx -c raw -w out.bin` (sanitized build aborts;
  `/mayhem/sp65_clean` silently corrupts the heap and may or may not crash).

## Cause

`ReadPCXFile()` (src/sp65/pcx.c, the "3 or 4 planes are RGB or RGBA" branch) advances the output
pixel pointer `Px` with `++Px` inside **each** per-plane copy loop:

```c
ReadPlane (F, P, L);
for (X = 0; X < P->Width; ++X, ++Px) { Px->C.R = L[X]; }   /* pcx.c:487 */
ReadPlane (F, P, L);
for (X = 0; X < P->Width; ++X, ++Px) { Px->C.G = L[X]; }
ReadPlane (F, P, L);
for (X = 0; X < P->Width; ++X, ++Px) { Px->C.B = L[X]; }
/* A plane (or clear): a fourth loop, again ++Px */
```

So one scanline moves `Px` forward by **4 x Width** pixels (R, G, B, A passes) although the bitmap
holds only `Width x Height` pixels. Already on row 0 the G pass writes into row 1's storage, and the
R pass of row 1 (the reproducer's crash site, pixel 16 of a 16-pixel bitmap) writes past the end of
the heap block. Every 3-/4-plane PCX triggers it — the file only has to be big enough to hold the
planes ReadPlane() asks for; the overflow size grows with `3 x Width x Height x sizeof(Pixel)`.

## Impact

Heap-buffer-overflow **write** of file-controlled bytes (the pixel values) beyond the bitmap
allocation, for any RGB/RGBA PCX handed to `sp65 -r`. That is memory corruption in a developer tool
processing possibly untrusted image assets (crash at best, silent heap corruption otherwise); as a
functional consequence, 24-bit PCX input has never worked in sp65.

## One-line upstream fix

Index the row instead of walking `Px` per plane, and advance once per row:

```c
for (X = 0; X < P->Width; ++X) { Px[X].C.R = L[X]; }   /* same for G, B, A */
...
Px += P->Width;   /* once, after all planes of this row */
```
