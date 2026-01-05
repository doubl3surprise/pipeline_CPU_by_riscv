#include "trap.h"

// A long-running workload intended for PC prediction evaluation.
// - Contains bubble-sort-like nested loops (loop/backward branches)
// - Contains if-heavy code (forward branches)
// - Contains call/return patterns (JALR/RET) via a small call chain
//
// It runs forever; use simulator options to stop and report:
//   --max-commit=800000 --pcpred-interval=50000

static volatile uint32_t sink = 0;
static uint32_t seed = 1;

static inline uint32_t lcg32(void) {
  seed = seed * 1664525u + 1013904223u;
  return seed;
}

#define N 64
static int a[N];

static void init_array(void) {
  for (int i = 0; i < N; i++) {
    a[i] = (int)(lcg32() & 0x3ffu) - 512;
  }
}

__attribute__((noinline)) static void bubble_sort_64(void) {
  // classic bubble sort (branchy inner loop)
  for (int j = 0; j < N; j++) {
    for (int i = 0; i < N - 1 - j; i++) {
      if (a[i] > a[i + 1]) {
        int t = a[i];
        a[i] = a[i + 1];
        a[i + 1] = t;
      }
    }
  }
}

__attribute__((noinline)) static uint32_t branchy_mix(uint32_t x) {
  // forward-branch heavy small state machine
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
    else if (m == 4) s += (uint32_t)i * 17u;
    else if (m == 5) s -= (uint32_t)i * 13u;
    else if (m == 6) s ^= (uint32_t)i * 29u;
    else s += (s & 0xffu);
  }
  return s;
}

__attribute__((noinline)) static uint32_t call3(uint32_t x) { return x * 33u + 1u; }
__attribute__((noinline)) static uint32_t call2(uint32_t x) { return call3(x ^ 0x5a5a5a5au) + 7u; }
__attribute__((noinline)) static uint32_t call1(uint32_t x) { return call2(x + 3u) ^ 0xa5a5a5a5u; }

int main(void) {
  // warm state
  sink ^= lcg32();
  init_array();

  for (uint32_t iter = 0;; iter++) {
    // refresh array periodically to avoid becoming fully sorted forever
    if ((iter & 15u) == 0) init_array();

    bubble_sort_64();

    // light checksum on sorted-ish data (loop branches)
    uint32_t acc = 0;
    for (int i = 0; i < N; i++) acc = (acc << 1) ^ (uint32_t)(a[i] + i);

    uint32_t bm = branchy_mix(seed ^ iter ^ acc);
    uint32_t cc = call1(bm) ^ call1(acc);

    sink ^= acc;
    sink ^= bm;
    sink ^= cc;
  }

  return 0;
}


