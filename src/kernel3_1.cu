#include <cuda.h>
#include <mma.h>
#include <cute/tensor.hpp>

#include "device_utils.cuh"
#include "structs_n_stuff.cuh"
#include "cute_utils.cuh"

using namespace cute;

// constexpr unsigned int maxThreadsPerBlock = 1024;
// constexpr unsigned int minBlocksPerMultiprocessor = 8;

template <unsigned int BM_dim,
unsigned int BN_dim,
unsigned int BK_dim,
unsigned int WM_dim,
unsigned int WN_dim,
unsigned int WK_dim,
unsigned int A_swizzle_bits,
unsigned int B_swizzle_bits>
__global__ void
kernel_2(half* A,
  half* B,
  half* C,
  half* D,
  const float alpha,
  const float beta,
  const unsigned int M,
  const unsigned int N,
  unsigned int K)
{

  constexpr unsigned int MMA_M_dim = 16;
  constexpr unsigned int MMA_N_dim = 8;
  constexpr unsigned int MMA_K_dim = 8;

  // loop bounds
  constexpr unsigned int mma_tiles_per_warp_k = WK_dim / MMA_K_dim;
  constexpr unsigned int mma_tiles_per_warp_m = WM_dim / MMA_M_dim;
  constexpr unsigned int mma_tiles_per_warp_n = WN_dim / MMA_N_dim;
  constexpr unsigned int warp_tiles_per_block_k = BK_dim / WK_dim;
  const unsigned int num_block_tiles_k = K / BK_dim;
  
  const unsigned int blocks_per_N = N / BN_dim;
  const unsigned int block_m = blockIdx.x / blocks_per_N;
  const unsigned int block_n = blockIdx.x % blocks_per_N;
  const unsigned int warp_m = threadIdx.y;
  const unsigned int warp_n = threadIdx.x / 32;

  auto A_block_tile_shape = make_shape(Int<BM_dim>{}, Int<BK_dim>{});
  auto B_block_tile_shape = make_shape(Int<BK_dim>{}, Int<BN_dim>{});
  auto CD_block_tile_shape = make_shape(Int<BM_dim>{}, Int<BN_dim>{});
  auto A_warp_tile_shape = make_shape(Int<WM_dim>{}, Int<WK_dim>{});
  auto B_warp_tile_shape = make_shape(Int<WK_dim>{}, Int<WN_dim>{});
  auto CD_warp_tile_shape = make_shape(Int<WM_dim>{}, Int<WN_dim>{});
  auto A_mma_tile_shape = make_shape(Int<MMA_M_dim>{}, Int<MMA_K_dim>{});
  auto B_mma_tile_shape = make_shape(Int<MMA_K_dim>{}, Int<MMA_N_dim>{});
  auto CD_mma_tile_shape = make_shape(Int<MMA_M_dim>{}, Int<MMA_N_dim>{});

  extern __shared__ half shmem[];
  half* A_smem_ = shmem;
  half* B_smem_ = &shmem[BM_dim * BK_dim];

  Tensor A_gmem = make_tensor(A, make_shape(M, K), LayoutRight{});
  Tensor B_gmem = make_tensor(B, make_shape(K, N), LayoutRight{});
  Tensor C_gmem = make_tensor(C, make_shape(M, N), LayoutRight{});
  Tensor D_gmem = make_tensor(D, make_shape(M, N), LayoutRight{});
  
  auto A_smem_layout = composition(Swizzle<3, 3, A_swizzle_bits>{}, make_layout(A_block_tile_shape, LayoutRight{}));
  auto B_smem_layout = composition(Swizzle<3, 3, B_swizzle_bits>{}, make_layout(B_block_tile_shape, LayoutRight{}));
  Tensor A_smem = make_tensor(make_smem_ptr(A_smem_), A_smem_layout);
  Tensor B_smem = make_tensor(make_smem_ptr(B_smem_), B_smem_layout);

  // block tile each matrix
  Tensor A_block_tiles = zipped_divide(A_gmem, A_block_tile_shape);
  Tensor B_block_tiles = zipped_divide(B_gmem, B_block_tile_shape);
  Tensor C_block_tiles = zipped_divide(C_gmem, CD_block_tile_shape);
  Tensor D_block_tiles = zipped_divide(D_gmem, CD_block_tile_shape);
  
  // create warp tiles for a,b inside of shared memory block tiles
  Tensor A_warp_tiles = zipped_divide(A_smem, A_warp_tile_shape);
  Tensor B_warp_tiles = zipped_divide(B_smem, B_warp_tile_shape);

  // create mma tiles for a,b inside of warp_tiles
  Tensor A_mma_tiles = coalesce(zipped_divide(A_warp_tiles, make_shape(A_mma_tile_shape)), Step<_1,Step<>>{});
  Tensor B_mma_tiles = coalesce(zipped_divide(B_warp_tiles, make_shape(B_mma_tile_shape)), Step<_1,Step<>>{});

  // create warp and mma tiles for c,d inside of global memory block tiles
  Tensor C_warp_tiles = coalesce(zipped_divide(C_block_tiles, make_shape(CD_warp_tile_shape)), Step<_1,_1>{});
  Tensor D_warp_tiles = coalesce(zipped_divide(D_block_tiles, make_shape(CD_warp_tile_shape)), Step<_1,_1>{});
  Tensor C_mma_tiles = coalesce(zipped_divide(C_warp_tiles, make_shape(CD_mma_tile_shape)), Step<_1,_1>{});
  Tensor D_mma_tiles = coalesce(zipped_divide(D_warp_tiles, make_shape(CD_mma_tile_shape)), Step<_1,_1>{});

  // declare register storage for accumulators
  half acc_register[mma_tiles_per_warp_m][mma_tiles_per_warp_n][4];
  for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
  {
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        acc_register[mma_m][mma_n][0] = 0;
        acc_register[mma_m][mma_n][1] = 0;
        acc_register[mma_m][mma_n][2] = 0;
        acc_register[mma_m][mma_n][3] = 0;
      }
  }

  for (unsigned int block_k = 0; block_k < num_block_tiles_k; block_k++)
  {
    Tensor A_block_tile = A_block_tiles(make_coord(_,_), make_coord(block_m, block_k));
    Tensor B_block_tile = B_block_tiles(make_coord(_,_), make_coord(block_k, block_n));
    tileMemcpySwizzle<BM_dim, BK_dim, A_swizzle_bits>(A_block_tile, A_smem, K, BK_dim);
    tileMemcpySwizzle<BK_dim, BN_dim, B_swizzle_bits>(B_block_tile, B_smem, N, BN_dim);
    __syncthreads();

    // preload tiles of a into registers
    for (unsigned int warp_k = 0; warp_k < warp_tiles_per_block_k; warp_k++)
    {
      // preload tiles of a into registers
      half A_mma_tile_reg[mma_tiles_per_warp_m][mma_tiles_per_warp_k][4];
      for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
      {
        for (unsigned int mma_k = 0; mma_k < mma_tiles_per_warp_k; mma_k++)
        {
          Tensor A_mma_tile = A_mma_tiles(make_coord(_,_), make_coord(make_coord(mma_m, mma_k), make_coord(warp_m, warp_k)));
          ldmatrix_m16n8(A_mma_tile, A_mma_tile_reg[mma_m][mma_k]);
        }
      }

      // preload tiles of b into registers
      half B_mma_tile_reg[mma_tiles_per_warp_k][mma_tiles_per_warp_n][2];
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        for (unsigned int mma_k = 0; mma_k < mma_tiles_per_warp_k; mma_k++)
        {
          Tensor B_mma_tile = B_mma_tiles(make_coord(_,_), make_coord(make_coord(mma_k, mma_n), make_coord(warp_k, warp_n)));
          ldmatrix_n8k8(B_mma_tile, B_mma_tile_reg[mma_k][mma_n]);
        }
      }

      // outer product between mma tiles
      for (unsigned int mma_k = 0; mma_k < mma_tiles_per_warp_k; mma_k++)
      {
        for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
        {
          for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
          {
            mma_sync_m16n8k8(
              acc_register[mma_m][mma_n],
              A_mma_tile_reg[mma_m][mma_k],
              B_mma_tile_reg[mma_k][mma_n],
              acc_register[mma_m][mma_n]
            );
          }
        }
      }
    }
    __syncthreads();
  }

  // epilogue
  half alpha_ = (half)alpha;
  half beta_ = (half)beta;
  half C_register[mma_tiles_per_warp_m][mma_tiles_per_warp_n][4];
  for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
  {
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        Tensor C_mma_tile = C_mma_tiles(make_coord(_,_), make_coord(mma_m, mma_n, warp_m, warp_n, block_m, block_n));
        ldmatrix_m16n8_gmem(C_mma_tile.data(), C_register[mma_m][mma_n], N * sizeof(half));
          
        // scale C by beta
        acc_register[mma_m][mma_n][0] = acc_register[mma_m][mma_n][0] * alpha_ + C_register[mma_m][mma_n][0] * beta_;
        acc_register[mma_m][mma_n][1] = acc_register[mma_m][mma_n][1] * alpha_ + C_register[mma_m][mma_n][1] * beta_;
        acc_register[mma_m][mma_n][2] = acc_register[mma_m][mma_n][2] * alpha_ + C_register[mma_m][mma_n][2] * beta_;
        acc_register[mma_m][mma_n][3] = acc_register[mma_m][mma_n][3] * alpha_ + C_register[mma_m][mma_n][3] * beta_;
      }
  }

  for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
  {
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        Tensor D_mma_tile = D_mma_tiles(make_coord(_,_), make_coord(mma_m, mma_n, warp_m, warp_n, block_m, block_n));
        stmatrix_m16n8(D_mma_tile.data(), acc_register[mma_m][mma_n], N * sizeof(half));
      }
  }
}

void kernel_2_launch(sgemm_params device_sgemm_params, KernelLogger& timer, const unsigned int num_runs = 10)
{
    
  constexpr unsigned int BM_dim = 256;
  constexpr unsigned int BN_dim = 128;
  constexpr unsigned int BK_dim = 64;
  
  constexpr unsigned int WARPS_PER_BLOCK_M = 4;
  constexpr unsigned int WARPS_PER_BLOCK_N = 2;
  constexpr unsigned int WARPS_PER_BLOCK_K = 2;

    constexpr unsigned int WM_dim = BM_dim / WARPS_PER_BLOCK_M;
    constexpr unsigned int WN_dim = BN_dim / WARPS_PER_BLOCK_N;
    constexpr unsigned int WK_dim = BK_dim / WARPS_PER_BLOCK_K;

    const unsigned int M = device_sgemm_params.M;
    const unsigned int N = device_sgemm_params.N;
    const unsigned int K = device_sgemm_params.K;

    assert(M % BM_dim == 0);
    assert(N % BN_dim == 0);
    assert(K % BK_dim == 0);
    
    constexpr unsigned int WARP_SIZE = 32;
    const unsigned int BlocksM = M / BM_dim;
    const unsigned int BlocksN = N / BN_dim;
    const unsigned int ThreadsM = WARPS_PER_BLOCK_M;
    const unsigned int ThreadsN = WARP_SIZE * WARPS_PER_BLOCK_N;
    const unsigned int shmem_bytes = (BM_dim * BK_dim + BK_dim * BN_dim) * sizeof(half);
    constexpr unsigned int A_swizzle_bits = int_log2(BK_dim/8);
    constexpr unsigned int B_swizzle_bits = int_log2(BN_dim/8);

    dim3 gridDim(BlocksN * BlocksM, 1);
    dim3 blockDim(ThreadsN, ThreadsM);
    
    CUDA_CHECK(cudaFuncSetAttribute(kernel_2<BM_dim, BN_dim, BK_dim, WM_dim, WN_dim, WK_dim, A_swizzle_bits, B_swizzle_bits>,
    cudaFuncAttributeMaxDynamicSharedMemorySize,
    65536)); // set shared memory limit to 64KB which is maximum for sm_75

    for (int i = 0; i < num_runs; i++)
    {
        timer.Start();
        kernel_2
        <BM_dim, BN_dim, BK_dim,
        WM_dim, WN_dim, WK_dim, A_swizzle_bits, B_swizzle_bits>
        <<<gridDim, blockDim, shmem_bytes>>>(
            device_sgemm_params.A,
            device_sgemm_params.B,
            device_sgemm_params.C,
            device_sgemm_params.D,
            device_sgemm_params.alpha,
            device_sgemm_params.beta,
            M,
            N,
            K
        );
        timer.Stop();
    }
    double gflops_per_sec = timer.logKernelStats(M, N, K);
    std::cout << gflops_per_sec << " GFLOPS/sec for " << M << "x" << N << "x" << K << std::endl;
    CUDA_CHECK(cudaPeekAtLastError());
}


