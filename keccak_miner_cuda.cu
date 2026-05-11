#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <cuda_runtime.h>

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t u8;

__constant__ u64 RC[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

__constant__ int ROTC[24] = {1,3,6,10,15,21,28,36,45,55,2,14,27,41,56,8,25,43,62,18,39,61,20,44};
__constant__ int PILN[24] = {10,7,11,17,18,3,5,16,8,21,24,4,15,23,19,13,12,2,20,14,22,9,6,1};

#define ROL64(x,n) (((x)<<(n))|((x)>>(64-(n))))

__device__ __forceinline__ uint64_t rotl64(uint64_t x, int n) {
    uint32_t lo = (uint32_t)x;
    uint32_t hi = (uint32_t)(x >> 32);
    uint32_t rlo, rhi;
    if (n < 32) {
        rlo = __funnelshift_l(hi, lo, n);
        rhi = __funnelshift_l(lo, hi, n);
    } else {
        rlo = __funnelshift_l(lo, hi, n - 32);
        rhi = __funnelshift_l(hi, lo, n - 32);
    }
    return ((uint64_t)rhi << 32) | rlo;
}

#undef ROL64
#define ROL64(x,n) rotl64((x), (n))

__device__ __forceinline__ u64 bswap64(u64 x) {
    x = ((x & 0x00FF00FF00FF00FFULL) << 8)  | ((x & 0xFF00FF00FF00FF00ULL) >> 8);
    x = ((x & 0x0000FFFF0000FFFFULL) << 16) | ((x & 0xFFFF0000FFFF0000ULL) >> 16);
    x = (x << 32) | (x >> 32);
    return x;
}

__device__ __forceinline__ void keccak_f(u64 *st) {
    u64 s0=st[0],s1=st[1],s2=st[2],s3=st[3],s4=st[4];
    u64 s5=st[5],s6=st[6],s7=st[7],s8=st[8],s9=st[9];
    u64 s10=st[10],s11=st[11],s12=st[12],s13=st[13],s14=st[14];
    u64 s15=st[15],s16=st[16],s17=st[17],s18=st[18],s19=st[19];
    u64 s20=st[20],s21=st[21],s22=st[22],s23=st[23],s24=st[24];

    #pragma unroll
    for (int r = 0; r < 24; r++) {
        u64 bc0 = s0 ^ s5 ^ s10 ^ s15 ^ s20;
        u64 bc1 = s1 ^ s6 ^ s11 ^ s16 ^ s21;
        u64 bc2 = s2 ^ s7 ^ s12 ^ s17 ^ s22;
        u64 bc3 = s3 ^ s8 ^ s13 ^ s18 ^ s23;
        u64 bc4 = s4 ^ s9 ^ s14 ^ s19 ^ s24;

        u64 d0 = bc4 ^ ROL64(bc1, 1);
        u64 d1 = bc0 ^ ROL64(bc2, 1);
        u64 d2 = bc1 ^ ROL64(bc3, 1);
        u64 d3 = bc2 ^ ROL64(bc4, 1);
        u64 d4 = bc3 ^ ROL64(bc0, 1);

        u64 n0  = s0  ^ d0;
        u64 n1  = ROL64(s6  ^ d1, 44);
        u64 n2  = ROL64(s12 ^ d2, 43);
        u64 n3  = ROL64(s18 ^ d3, 21);
        u64 n4  = ROL64(s24 ^ d4, 14);
        u64 n5  = ROL64(s3  ^ d3, 28);
        u64 n6  = ROL64(s9  ^ d4, 20);
        u64 n7  = ROL64(s10 ^ d0, 3);
        u64 n8  = ROL64(s16 ^ d1, 45);
        u64 n9  = ROL64(s22 ^ d2, 61);
        u64 n10 = ROL64(s1  ^ d1, 1);
        u64 n11 = ROL64(s7  ^ d2, 6);
        u64 n12 = ROL64(s13 ^ d3, 25);
        u64 n13 = ROL64(s19 ^ d4, 8);
        u64 n14 = ROL64(s20 ^ d0, 18);
        u64 n15 = ROL64(s4  ^ d4, 27);
        u64 n16 = ROL64(s5  ^ d0, 36);
        u64 n17 = ROL64(s11 ^ d1, 10);
        u64 n18 = ROL64(s17 ^ d2, 15);
        u64 n19 = ROL64(s23 ^ d3, 56);
        u64 n20 = ROL64(s2  ^ d2, 62);
        u64 n21 = ROL64(s8  ^ d3, 55);
        u64 n22 = ROL64(s14 ^ d4, 39);
        u64 n23 = ROL64(s15 ^ d0, 41);
        u64 n24 = ROL64(s21 ^ d1, 2);

        s0  = n0  ^ (~n1  & n2);
        s1  = n1  ^ (~n2  & n3);
        s2  = n2  ^ (~n3  & n4);
        s3  = n3  ^ (~n4  & n0);
        s4  = n4  ^ (~n0  & n1);
        s5  = n5  ^ (~n6  & n7);
        s6  = n6  ^ (~n7  & n8);
        s7  = n7  ^ (~n8  & n9);
        s8  = n8  ^ (~n9  & n5);
        s9  = n9  ^ (~n5  & n6);
        s10 = n10 ^ (~n11 & n12);
        s11 = n11 ^ (~n12 & n13);
        s12 = n12 ^ (~n13 & n14);
        s13 = n13 ^ (~n14 & n10);
        s14 = n14 ^ (~n10 & n11);
        s15 = n15 ^ (~n16 & n17);
        s16 = n16 ^ (~n17 & n18);
        s17 = n17 ^ (~n18 & n19);
        s18 = n18 ^ (~n19 & n15);
        s19 = n19 ^ (~n15 & n16);
        s20 = n20 ^ (~n21 & n22);
        s21 = n21 ^ (~n22 & n23);
        s22 = n22 ^ (~n23 & n24);
        s23 = n23 ^ (~n24 & n20);
        s24 = n24 ^ (~n20 & n21);

        s0 ^= RC[r];
    }

    st[0]=s0;  st[1]=s1;  st[2]=s2;  st[3]=s3;  st[4]=s4;
}

struct Result {
    int found;
    u64 nonce;
};

__global__ void mine_kernel(
    u64 c0, u64 c1, u64 c2, u64 c3,
    u64 t0, u64 t1, u64 t2, u64 t3,
    u64 nonce_base,
    Result *result
) {
    u64 nonce = nonce_base + (u64)blockIdx.x * blockDim.x + threadIdx.x;

    u64 s[25];
    s[0] = c0;
    s[1] = c1;
    s[2] = c2;
    s[3] = c3;
    s[4] = 0;
    s[5] = 0;
    s[6] = 0;
    s[7] = bswap64(nonce);
    s[8] = 0x01ULL;
    #pragma unroll
    for (int i = 9; i < 16; i++) s[i] = 0;
    s[16] = 0x8000000000000000ULL;
    #pragma unroll
    for (int i = 17; i < 25; i++) s[i] = 0;

    keccak_f(s);

    u64 h0 = bswap64(s[0]);
    if (h0 < t0) {
        if (atomicCAS(&result->found, 0, 1) == 0) result->nonce = nonce;
        return;
    }
    if (h0 == t0) {
        u64 h1 = bswap64(s[1]);
        if (h1 < t1) {
            if (atomicCAS(&result->found, 0, 1) == 0) result->nonce = nonce;
            return;
        }
        if (h1 == t1) {
            u64 h2 = bswap64(s[2]);
            if (h2 < t2 || (h2 == t2 && bswap64(s[3]) < t3)) {
                if (atomicCAS(&result->found, 0, 1) == 0) result->nonce = nonce;
            }
        }
    }
}

static u8 hb(char c) { return c>='a'?c-'a'+10:c>='A'?c-'A'+10:c-'0'; }

static u64 load_u64_le(const u8 *b) {
    u64 v = 0;
    for (int i = 0; i < 8; i++) v |= ((u64)b[i]) << (i * 8);
    return v;
}

static u64 load_u64_be(const u8 *b) {
    u64 v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | b[i];
    return v;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <challenge_hex> <target_hex>\n", argv[0]);
        return 1;
    }

    const char *ch = argv[1] + (argv[1][0]=='0' && argv[1][1]=='x' ? 2 : 0);
    const char *tg = argv[2] + (argv[2][0]=='0' && argv[2][1]=='x' ? 2 : 0);

    u8 challenge[32], target[32];
    for (int i = 0; i < 32; i++) challenge[i] = (hb(ch[i*2])<<4)|hb(ch[i*2+1]);
    for (int i = 0; i < 32; i++) target[i]    = (hb(tg[i*2])<<4)|hb(tg[i*2+1]);

    u64 c0 = load_u64_le(challenge + 0);
    u64 c1 = load_u64_le(challenge + 8);
    u64 c2 = load_u64_le(challenge + 16);
    u64 c3 = load_u64_le(challenge + 24);

    u64 t0 = load_u64_be(target + 0);
    u64 t1 = load_u64_be(target + 8);
    u64 t2 = load_u64_be(target + 16);
    u64 t3 = load_u64_be(target + 24);

    Result *d_result;
    Result h_result = {0, 0};
    cudaMalloc(&d_result, sizeof(Result));

    const int THREADS = 256;
    const u64 BATCH   = 1ULL << 26;
    const int BLOCKS  = (int)(BATCH / THREADS);

    srand(time(NULL));
    u64 nonce_base = ((u64)rand() << 32) | (u32)rand();

    u64 total = 0;
    struct timespec t_now, t_last;
    clock_gettime(CLOCK_MONOTONIC, &t_last);

    while (1) {
        cudaMemcpy(d_result, &h_result, sizeof(Result), cudaMemcpyHostToDevice);
        mine_kernel<<<BLOCKS, THREADS>>>(c0, c1, c2, c3, t0, t1, t2, t3, nonce_base, d_result);
        cudaDeviceSynchronize();
        cudaMemcpy(&h_result, d_result, sizeof(Result), cudaMemcpyDeviceToHost);

        total += BATCH;
        nonce_base += BATCH;

        if (h_result.found) {
            u64 n = h_result.nonce;
            printf("FOUND:");
            for (int i = 0; i < 24; i++) printf("00");
            for (int i = 7; i >= 0; i--) printf("%02x", (u8)(n >> (i * 8)));
            printf("\n");
            fflush(stdout);
            break;
        }

        clock_gettime(CLOCK_MONOTONIC, &t_now);
        double elapsed = (t_now.tv_sec - t_last.tv_sec) + (t_now.tv_nsec - t_last.tv_nsec) / 1e9;
        if (elapsed >= 2.0) {
            double hps = (double)total / elapsed;
            fprintf(stderr, "PROGRESS:0:%llu\n", (unsigned long long)hps);
            fflush(stderr);
            t_last = t_now;
            total = 0;
        }
    }

    cudaFree(d_result);
    return 0;
}
