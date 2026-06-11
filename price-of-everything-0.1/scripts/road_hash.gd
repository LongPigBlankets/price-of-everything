class_name RoadHash
extends RefCounted
## Explicit FNV-1a hashing for every roads-v2 seed. GDScript's hash() is not
## guaranteed stable across engine versions, and the road network persists in
## saves — seeds must survive engine upgrades byte-for-byte.

# 0xCBF29CE484222325 as a signed 64-bit literal (GDScript ints are signed;
# the unsigned hex form overflows at parse time). Arithmetic wraps, which is
# exactly what FNV wants.
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 0x100000001B3

static func fnv1a(text: String) -> int:
	var h := FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = (h ^ b) * FNV_PRIME
	return h & 0x7FFFFFFFFFFFFFFF

## Deterministic pick of one of n options for a salted key.
static func pick(text: String, n: int) -> int:
	return int(fnv1a(text) % maxi(n, 1))

## Deterministic float in [-0.5, 0.5] for per-cell jitter.
static func jitter01(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return (float(h % 10000) / 9999.0) - 0.5
