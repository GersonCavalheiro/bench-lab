#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

static double segundos(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static void *alocar(size_t bytes) {
    void *p = malloc(bytes);
    if (!p) { perror("malloc"); exit(EXIT_FAILURE); }
    return p;
}

static void inicializar(int32_t *a, int32_t *b, size_t n) {
    for (size_t i = 0; i < n * n; ++i) {
        a[i] = (int32_t)((i * 17u + 3u) % 7u) - 3;
        b[i] = (int32_t)((i * 13u + 5u) % 7u) - 3;
    }
}

static void multiplicar(const int32_t *restrict A,
                        const int32_t *restrict B,
                        int32_t *restrict C, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        for (size_t k = 0; k < n; ++k) {
            const int32_t a = A[i*n+k];
            for (size_t j = 0; j < n; ++j)
                C[i*n+j] += a * B[k*n+j];
        }
    }
}

int main(int argc, char **argv) {
    size_t n = 384;
    if (argc > 2) { fprintf(stderr, "Uso: %s [N]\n", argv[0]); return 1; }
    if (argc == 2) {
        char *fim;
        unsigned long v = strtoul(argv[1], &fim, 10);
        if (*argv[1] == '\0' || *fim || v == 0 || v > 1024) {
            fprintf(stderr, "N deve estar entre 1 e 1024\n"); return 1;
        }
        n = (size_t)v;
    }
    if (n > SIZE_MAX / n / sizeof(int32_t)) return 1;
    size_t bytes = n*n*sizeof(int32_t);
    int32_t *A = alocar(bytes), *B = alocar(bytes), *C = calloc(n*n, sizeof(*C));
    if (!C) { perror("calloc"); return 1; }
    inicializar(A, B, n);
    double inicio = segundos();
    multiplicar(A, B, C, n);
    double tempo = segundos()-inicio;
    int64_t checksum = 0;
    for (size_t i = 0; i < n*n; ++i) checksum += C[i];
    printf("versao=eficiente n=%zu tempo=%.6f checksum=%lld\n", n, tempo, (long long)checksum);
    free(A); free(B); free(C);
    return 0;
}

