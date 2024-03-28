#pragma once
#include "cuda_runtime.h"
#include <cuda_fp16.h>
#include <iostream>

/**
 * Panic wrapper for unwinding CUDA runtime errors
 */
#define CUDA_CHECK(status)                                              \
  {                                                                     \
    cudaError_t error = status;                                         \
    if (error != cudaSuccess) {                                         \
      std::cerr << "Got bad cuda status: " << cudaGetErrorString(error) \
                << " at line: " << __LINE__ << std::endl;               \
      exit(EXIT_FAILURE);                                               \
    }                                                                   \
  }


// struct with generic type
template <typename T>
struct sgemm_params
{
  T* A;
  T* B;
  T* C;
  T* D;
  float alpha;
  float beta;
  unsigned int M;
  unsigned int N;
  unsigned int K;
};

template <typename T>
std::pair<sgemm_params<T>, sgemm_params<T>> sgemm_setup(unsigned int M, unsigned int N, unsigned int K, float alpha = 0.7, float beta = 0.3)
{
    // setup
    T *A, *B, *C, *D;
    A = (T *)malloc(M * K * sizeof(T));
    B = (T *)malloc(K * N * sizeof(T));
    C = (T *)malloc(M * N * sizeof(T));
    D = (T *)malloc(M * N * sizeof(T));

    // allocate device matrices
    T *dev_A, *dev_B, *dev_C, *dev_D;
    CUDA_CHECK(cudaMalloc((void **)&dev_A, M * K * sizeof(T)));
    CUDA_CHECK(cudaMalloc((void **)&dev_B, K * N * sizeof(T)));
    CUDA_CHECK(cudaMalloc((void **)&dev_C, M * N * sizeof(T)));
    CUDA_CHECK(cudaMalloc((void **)&dev_D, M * N * sizeof(T)));

    // fill host matrices with random elements
    srand(1234);
    for (int i = 0; i < M * N; i++) {
      C[i] = (T)(rand() % 10);
    }
    for (int i = 0; i < K * N; i++)
    {
      B[i] = (T)(rand() % 10);
    }
    for (int i = 0; i < M * K; i++)
    {
      A[i] = (T)(rand() % 10);
    }
    
    // copy to device
    CUDA_CHECK(cudaMemcpy(dev_A, A, M * K * sizeof(T), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dev_B, B, K * N * sizeof(T), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dev_C, C, M * N * sizeof(T), cudaMemcpyHostToDevice));

    sgemm_params<T> device_sgemm_params = {dev_A, dev_B, dev_C, dev_D, alpha, beta, M, N, K};
    sgemm_params<T> host_sgemm_params = {A, B, C, D, alpha, beta, M, N, K};
    return std::make_pair(device_sgemm_params, host_sgemm_params);
}


// template <>
void host_sgemm(sgemm_params<half> params)
{
    half *A = params.A;
    half *B = params.B;
    half *C = params.C;
    half *D = params.D;
    float alpha = params.alpha;
    float beta = params.beta;
    unsigned int M = params.M;
    unsigned int N = params.N;
    unsigned int K = params.K;

    for (int m = 0; m < M; m++)
    {
    for (int n = 0; n < N; n++)
    {
        
        float acc = 0.0f;
        for (int k = 0; k < K; k++)
        {
        acc += (float) (A[m * K + k] * B[k * N + n]);
        }
        D[m * N + n] = alpha * acc + (float) ((half) beta * C[m * N + n]);
    }
    }
}

void host_sgemm(sgemm_params<float> params)
{
    throw std::runtime_error("Not implemented");
}

template <typename T>
bool elementwise_isclose(T* a, T* b, int size, float atol = 1e-5)
{
    for (int i = 0; i < size; i++)
    {
        if (std::abs((float) a[i] - (float) b[i]) > atol)
        {
            return false;
        }
    }
    return true;
}

template <typename T>
void sgemm_verify(sgemm_params<T> device_sgemm_params, sgemm_params<T> host_sgemm_params)
{
    const unsigned int M = host_sgemm_params.M;
    const unsigned int N = host_sgemm_params.N;
    T *D = (T *)malloc(M * N * sizeof(T));
    CUDA_CHECK(cudaMemcpy(D, device_sgemm_params.D, M * N * sizeof(T), cudaMemcpyDeviceToHost));
    host_sgemm(host_sgemm_params);
    assert(elementwise_isclose(D, host_sgemm_params.D, M * N));
}