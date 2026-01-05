#include "trap.h"

// pcpred-mix-800k: Mixed classic algorithms + randomized control-flow.
//
// Goal: stress PC prediction with a realistic mix:
// - for-loops (tight backward branches)
// - if/else chains (forward branches)
// - function call/return (JAL/JALR/RET) including recursion (quicksort)
// - classic kernels: bubble sort, quicksort, linear sieve, matrix multiply
//
// NOTE: This program runs forever. Use simulator to stop at a fixed commit window:
//   --max-commit=800000 --pcpred-interval=50000
//
// You can tune behavior by changing:
// - kernel sizes (N_* macros)
// - scheduling weights (case distribution)
// - PRNG seed

static volatile uint32_t sink = 0;

// ---- Deterministic PRNG (LCG) ----
static uint32_t seed = 1;
static inline uint32_t lcg32(void) {
  seed = seed * 1664525u + 1013904223u;
  return seed;
}

// ---- Branchy state machine (if/else heavy) ----
__attribute__((noinline)) static uint32_t branchy_state(uint32_t x) {
  uint32_t s = x;
  for (int i = 0; i < 256; i++) {
    s ^= (s << 13);
    s ^= (s >> 17);
    s ^= (s << 5);
    uint32_t m = s & 15u;
    if (m == 0) s += 0x1234u;
    else if (m == 1) s ^= 0x9e3779b9u;
    else if (m == 2) s = (s << 1) | (s >> 31);
    else if (m == 3) s = (s >> 1) | (s << 31);
    else if (m == 4) s += (uint32_t)i * 17u;
    else if (m == 5) s -= (uint32_t)i * 13u;
    else if (m == 6) s ^= (uint32_t)i * 29u;
    else if (m == 7) s += (s & 0xffu);
    else if (m == 8) s ^= (s >> 3);
    else if (m == 9) s += (s << 7);
    else if (m == 10) s ^= (uint32_t)(i * 3);
    else if (m == 11) s = (s << 9) ^ (s >> 5);
    else if (m == 12) s += 0x3141592u;
    else if (m == 13) s ^= 0x2718281u;
    else if (m == 14) s += (s ^ (uint32_t)i);
    else s ^= (s + (uint32_t)i);
  }
  return s;
}

// ---- Call/return chain (JALR/RET) ----
__attribute__((noinline)) static uint32_t call3(uint32_t x) { return x * 33u + 1u; }
__attribute__((noinline)) static uint32_t call2(uint32_t x) { return call3(x ^ 0x5a5a5a5au) + 7u; }
__attribute__((noinline)) static uint32_t call1(uint32_t x) { return call2(x + 3u) ^ 0xa5a5a5a5u; }

// ---- Bubble sort ----
#define N_BUB 64
static int bub[N_BUB];
static void init_bubble(void) {
  for (int i = 0; i < N_BUB; i++) bub[i] = (int)(lcg32() & 0x3ffu) - 512;
}
__attribute__((noinline)) static void bubble_sort(void) {
  for (int j = 0; j < N_BUB; j++) {
    for (int i = 0; i < N_BUB - 1 - j; i++) {
      if (bub[i] > bub[i + 1]) {
        int t = bub[i];
        bub[i] = bub[i + 1];
        bub[i + 1] = t;
      }
    }
  }
}

// ---- Quicksort (recursive; RAS-heavy) ----
#define N_QS 128
static int qs[N_QS];
static void init_qs(void) {
  for (int i = 0; i < N_QS; i++) qs[i] = (int)(lcg32() & 0x7ffu) - 1024;
}
static inline void iswap(int *a, int *b) {
  int t = *a; *a = *b; *b = t;
}
__attribute__((noinline)) static int partition(int *arr, int lo, int hi) {
  int pivot = arr[hi];
  int i = lo - 1;
  for (int j = lo; j < hi; j++) {
    if (arr[j] <= pivot) {
      i++;
      iswap(&arr[i], &arr[j]);
    }
  }
  iswap(&arr[i + 1], &arr[hi]);
  return i + 1;
}
__attribute__((noinline)) static void quicksort(int *arr, int lo, int hi) {
  if (lo < hi) {
    int p = partition(arr, lo, hi);
    quicksort(arr, lo, p - 1);
    quicksort(arr, p + 1, hi);
  }
}

// ---- Linear sieve ----
#define N_SIEVE 4096
static uint8_t is_comp[N_SIEVE + 1];
static int primes[N_SIEVE];
__attribute__((noinline)) static int linear_sieve(void) {
  for (int i = 0; i <= N_SIEVE; i++) is_comp[i] = 0;
  int pcnt = 0;
  for (int i = 2; i <= N_SIEVE; i++) {
    if (!is_comp[i]) primes[pcnt++] = i;
    for (int j = 0; j < pcnt; j++) {
      int p = primes[j];
      int x = i * p;
      if (x > N_SIEVE) break;
      is_comp[x] = 1;
      if (i % p == 0) break;
    }
  }
  return pcnt;
}

// ---- Matrix multiply ----
#define N_MM 16
static int A[N_MM][N_MM], B[N_MM][N_MM], C[N_MM][N_MM];
static void init_mm(void) {
  for (int i = 0; i < N_MM; i++) {
    for (int j = 0; j < N_MM; j++) {
      A[i][j] = (int)(lcg32() & 0xffu) - 128;
      B[i][j] = (int)(lcg32() & 0xffu) - 128;
      C[i][j] = 0;
    }
  }
}
__attribute__((noinline)) static int matmul(void) {
  for (int i = 0; i < N_MM; i++) {
    for (int j = 0; j < N_MM; j++) {
      int sum = 0;
      for (int k = 0; k < N_MM; k++) {
        sum += A[i][k] * B[k][j];
      }
      C[i][j] = sum;
    }
  }
  return C[(seed >> 3) & (N_MM - 1)][(seed >> 7) & (N_MM - 1)];
}

int main(void) {
  // warm some state
  sink ^= lcg32();
  init_bubble();
  init_qs();
  init_mm();

  // Run forever; simulator limits commit count.
  for (uint32_t iter = 0;; iter++) {
    // periodically refresh inputs so branch patterns shift over time (more interesting for predictors)
    if ((iter & 7u) == 0) init_bubble();
    if ((iter & 15u) == 0) init_qs();
    if ((iter & 31u) == 0) init_mm();

    // pseudo-random scheduling of kernels (deterministic)
    uint32_t r = lcg32();
    switch (r & 7u) {
      case 0:
      case 1: {
        bubble_sort();
        // small checksum loop (more backward branches)
        uint32_t acc = 0;
        for (int i = 0; i < N_BUB; i++) acc = (acc << 1) ^ (uint32_t)(bub[i] + i);
        sink ^= acc;
        break;
      }
      case 2:
      case 3: {
        quicksort(qs, 0, N_QS - 1);
        // pick a few elements to prevent dead-code elimination
        sink ^= (uint32_t)qs[(r >> 8) & (N_QS - 1)];
        sink ^= (uint32_t)qs[(r >> 16) & (N_QS - 1)];
        break;
      }
      case 4: {
        int pcnt = linear_sieve();
        sink ^= (uint32_t)pcnt;
        break;
      }
      case 5: {
        int v = matmul();
        sink ^= (uint32_t)v;
        break;
      }
      case 6: {
        uint32_t bm = branchy_state(seed ^ iter ^ r);
        uint32_t cc = call1(bm) ^ call1(r);
        sink ^= bm;
        sink ^= cc;
        break;
      }
      default: {
        // small mixed arithmetic + if/else to keep control-flow diverse
        uint32_t x = seed ^ r ^ iter;
        for (int i = 0; i < 128; i++) {
          x = (x << 5) ^ (x >> 7) ^ (uint32_t)i;
          if (x & 1u) x += 3u;
          else x ^= 0xdeadbeefu;
        }
        sink ^= x;
        break;
      }
    }
  }

  return 0;
}


