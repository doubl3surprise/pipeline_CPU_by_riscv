#include "trap.h"

// A classic-algorithm mixed workload for PC prediction evaluation.
// - Contains loop-heavy kernels (matrix mul, sieve)
// - Contains if-heavy kernels (branchy state machine, conditional reductions)
// - Contains regular call/return patterns (shallow call chain)
// - Runs forever; use simulator option: --max-commit=50000 to stop at a fixed window.

static volatile uint32_t sink = 0;
static uint32_t seed = 1;

static inline uint32_t lcg32() {
  seed = seed * 1664525u + 1013904223u;
  return seed;
}

static uint32_t crc32_simple(const uint8_t *buf, int n) {
  uint32_t crc = 0xffffffffu;
  for (int i = 0; i < n; i++) {
    crc ^= buf[i];
    for (int b = 0; b < 8; b++) {
      uint32_t mask = -(crc & 1u);
      crc = (crc >> 1) ^ (0xedb88320u & mask);
    }
  }
  return ~crc;
}

static int sieve_count_primes(int n) {
  static uint8_t is_prime[2048 + 1];
  for (int i = 0; i <= n; i++) is_prime[i] = 1;
  is_prime[0] = is_prime[1] = 0;
  for (int p = 2; p * p <= n; p++) {
    if (is_prime[p]) {
      for (int k = p * p; k <= n; k += p) is_prime[k] = 0;
    }
  }
  int cnt = 0;
  for (int i = 2; i <= n; i++) cnt += is_prime[i];
  return cnt;
}

static int matmul8() {
  static int a[8][8], b[8][8], c[8][8];
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      a[i][j] = (int)(lcg32() & 0xff) - 128;
      b[i][j] = (int)(lcg32() & 0xff) - 128;
      c[i][j] = 0;
    }
  }
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      int sum = 0;
      for (int k = 0; k < 8; k++) {
        sum += a[i][k] * b[k][j];
      }
      c[i][j] = sum;
    }
  }
  return c[(seed >> 3) & 7][(seed >> 7) & 7];
}

static uint32_t branchy_mix(uint32_t x) {
  // if-heavy: dependent branches + small state machine
  uint32_t s = x;
  for (int i = 0; i < 256; i++) {
    s ^= (s << 13);
    s ^= (s >> 17);
    s ^= (s << 5);
    uint32_t m = s & 7u;
    if (m == 0) s += 0x1234u;
    else if (m == 1) s ^= 0x9e3779b9u;
    else if (m == 2) s = (s << 1) | (s >> 31);
    else if (m == 3) s = (s >> 1) | (s << 31);
    else if (m == 4) s += (i * 17u);
    else if (m == 5) s -= (i * 13u);
    else if (m == 6) s ^= (i * 29u);
    else s += (s & 0xffu);
  }
  return s;
}

__attribute__((noinline)) static uint32_t call_chain3(uint32_t x);
__attribute__((noinline)) static uint32_t call_chain2(uint32_t x) { return call_chain3(x ^ 0x5a5a5a5au) + 7u; }
__attribute__((noinline)) static uint32_t call_chain1(uint32_t x) { return call_chain2(x + 3u) ^ 0xa5a5a5a5u; }
__attribute__((noinline)) static uint32_t call_chain3(uint32_t x) { return x * 33u + 1u; }

int main() {
  static uint8_t buf[512];
  for (int i = 0; i < (int)sizeof(buf); i++) buf[i] = (uint8_t)i;

  // Warm some state
  sink ^= lcg32();

  for (uint32_t iter = 0; ; iter++) {
    // mix input a bit
    for (int i = 0; i < (int)sizeof(buf); i++) buf[i] ^= (uint8_t)lcg32();

    uint32_t c = crc32_simple(buf, (int)sizeof(buf));
    int primes = sieve_count_primes(1024 + (int)(seed & 511u));
    int mm = matmul8();
    uint32_t bm = branchy_mix(seed ^ iter);
    uint32_t cc = call_chain1(bm) ^ call_chain1(c);

    // prevent optimizing away
    sink ^= (uint32_t)primes;
    sink ^= (uint32_t)mm;
    sink ^= c;
    sink ^= bm;
    sink ^= cc;
  }

  return 0;
}


