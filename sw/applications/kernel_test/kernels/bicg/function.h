#ifndef _CGRA_FUNCTION_H_
#define _CGRA_FUNCTION_H_

#include <stdio.h>
#include <stdlib.h>

#define M 20
#define N 30

#define DECIMALS 15
typedef int32_t dtype;
typedef int64_t accum_t;

// #define DECIMALS 0
// typedef float dtype;
// typedef float accum_t;

// The BiCG kernel function
void bicg(dtype *A, // Matrix A of size n x m
          dtype *s,    // Vector s of size m
          dtype *q,    // Vector q of size n
          dtype *p,    // Vector p of size m
          dtype *r)    // Vector r of size n
{
    int i, j;

    // Main computation
    for (i = 0; i < M; i++) {
        s[i] = 0;
    }

    for (i = 0; i < N; i++) {
        q[i] = 0;  
        for (j = 0; j < M; j++) {
            dtype rA = (dtype)((accum_t)((accum_t)r[i] * (accum_t)A[i*M + j]) >> DECIMALS); // Fixed-point multiplication
            s[j] = s[j] + rA; 
            dtype pA = (dtype)((accum_t)((accum_t)A[i*M + j] * (accum_t)p[j]) >> DECIMALS); // Fixed-point multiplication
            q[i] = q[i] + pA; 
        }
    }

}

// // Main function to test the kernel
// int main()
// {
//     int n = 1000; // Number of rows
//     int m = 1000; // Number of columns

//     // Declare arrays (matrix A and vectors s, q, p, r)
//     float A[n][m];
//     float s[m];
//     float q[n];
//     float p[m];
//     float r[n];

//     // Initialize matrix A and vectors p, r with some sample values
//     for (int i = 0; i < n; i++) {
//         r[i] = (float)i / n;  // Initialize vector r
//         for (int j = 0; j < m; j++) {
//             A[i][j] = (float)(i * j) / (n * m); // Initialize matrix A
//         }
//     }

//     // Initialize vector p
//     for (int i = 0; i < m; i++) {
//         p[i] = (float)i / m;  // Initialize vector p
//     }

//     // Run the BiCG kernel
//     kernel_bicg(m, n, A, s, q, p, r);

//     // Output result for verification (printing a few elements)
//     printf("s[0]: %f, s[m-1]: %f\n", s[0], s[m-1]);
//     printf("q[0]: %f, q[n-1]: %f\n", q[0], q[n-1]);

//     return 0;
// }

#endif // _CGRA_FUNCTION_H_
