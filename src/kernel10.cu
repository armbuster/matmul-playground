#include <cuda.h>
#include <mma.h>
#include <cute/tensor.hpp>

#include "device_utils.cuh"
#include "structs_n_stuff.cuh"
#include "cute_utils.cuh"

using namespace cute;

__constant__ unsigned int increment_xor_patterns_A[2] = {0b10000, 0b110000};
__constant__ unsigned int increment_xor_patterns_B[2] = {0b0, 0b111000};


template <unsigned int _A_smem_stride_elements>
struct WarpTileIteratorA {
  half* _ptr;
  unsigned int _offset;
  unsigned int _count;

  __device__ __forceinline__ WarpTileIteratorA(half* ptr) : _ptr(ptr), _offset(0), _count(0) {
    _offset = (threadIdx.x % 32) * _A_smem_stride_elements; // logical offset
    _offset = _offset ^ ((_offset & 0b10000000) >> 4); // apply swizzle 1
    _offset = _offset ^ ((_offset & 0b1100000) >> 2);  // apply swizzle 2
    _offset = cvta_to_shared_u32(_ptr + _offset); // convert to shmem address
  }

  __device__ __forceinline__ uint32_t operator()(const unsigned int index) const {
    return _offset + index * 32 * _A_smem_stride_elements;
  }

  __device__ __forceinline__ void operator++() {
    _offset ^= increment_xor_patterns_A[_count % 2];
    _count++;
  }
};


template <unsigned int _B_smem_stride_elements>
struct WarpTileIteratorB {
  half* _ptr;
  unsigned int _offset;
  unsigned int _count;

  __device__ __forceinline__ WarpTileIteratorB(half* ptr) : _ptr(ptr), _offset(0), _count(0) {
    const unsigned int thread_group = (threadIdx.x % 32) / 8;
    const unsigned int thread_row = threadIdx.x % 8;
    _offset = (thread_row * _B_smem_stride_elements) + (thread_group * 8); // logical offset
    _offset = _offset ^ ((_offset & 0b1111000000) >> 4); // swizzled offset
    _offset = cvta_to_shared_u32(_ptr + _offset); // convert to shmem address

  }

  __device__ __forceinline__ uint32_t operator()(const unsigned int index) const {
    return (_offset ^ increment_xor_patterns_B[_count % 2]) + _count * 8 * _B_smem_stride_elements + index * 32;
  }

  __device__ __forceinline__ void operator++() {
    _count = (_count + 1) % 4;
  }
};




template <unsigned int BM_dim,
unsigned int BN_dim,
unsigned int BK_dim,
unsigned int WM_dim,
unsigned int WN_dim,
unsigned int WK_dim,
unsigned int num_threads>
__global__ void
kernel_10(half* A,
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
  const unsigned int block_tiles_k = K / BK_dim;
  
  // const unsigned int blocks_per_M = M / BM_dim;
  const unsigned int blocks_per_N = N / BN_dim;
  // auto swizzle_tile_dim = Int<4>{};
  // const int block_swizzle_tiles_per_M = blocks_per_M / swizzle_tile_dim;
  // const int block_swizzle_tiles_per_N = blocks_per_N / swizzle_tile_dim;
  // Layout block_n_map = make_layout(
  //   make_shape(swizzle_tile_dim, swizzle_tile_dim, block_swizzle_tiles_per_N, block_swizzle_tiles_per_M),
  //   make_stride(1 ,0, swizzle_tile_dim, 0)
  // );

  // Layout block_m_map = make_layout(
  //     make_shape(swizzle_tile_dim, swizzle_tile_dim, block_swizzle_tiles_per_N, block_swizzle_tiles_per_M),
  //     make_stride(0, 1, 0, swizzle_tile_dim)
  // );
  
  // const unsigned int block_m = block_m_map(blockIdx.x);
  // const unsigned int block_n = block_n_map(blockIdx.x);
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

  // block tile each matrix
  Tensor A_block_tiles = zipped_divide(A_gmem, A_block_tile_shape);
  Tensor B_block_tiles = zipped_divide(B_gmem, B_block_tile_shape);
  Tensor C_block_tiles = zipped_divide(C_gmem, CD_block_tile_shape);
  Tensor D_block_tiles = zipped_divide(D_gmem, CD_block_tile_shape);
  
  // create warp tiles for a,b inside of shared memory block tiles
  // Tensor A_warp_tiles = coalesce(zipped_divide(A_smem, A_warp_tile_shape), Step<_1,Step<>>{});
  // Tensor B_warp_tiles = coalesce(zipped_divide(B_smem, B_warp_tile_shape), Step<_1,Step<>>{});
  // Tensor B_warp_tiles = zipped_divide(B_smem, B_warp_tile_shape);
  // if (thread0())
  // {
  //   print(A_warp_tiles.layout());
  // }

  // create mma tiles for a,b inside of warp_tiles
  // Tensor A_mma_tiles = coalesce(zipped_divide(A_warp_tiles, make_shape(A_mma_tile_shape)), Step<_1,Step<>>{});
  // Tensor B_mma_tiles = coalesce(zipped_divide(B_warp_tiles, make_shape(B_mma_tile_shape)), Step<_1,Step<>>{});

  // create warp and mma tiles for c,d inside of global memory block tiles
  Tensor C_warp_tiles = coalesce(zipped_divide(C_block_tiles, make_shape(CD_warp_tile_shape)), Step<_1,_1>{});
  Tensor D_warp_tiles = coalesce(zipped_divide(D_block_tiles, make_shape(CD_warp_tile_shape)), Step<_1,_1>{});
  Tensor C_mma_tiles = coalesce(zipped_divide(C_warp_tiles, make_shape(CD_mma_tile_shape)), Step<_1,_1>{});
  Tensor D_mma_tiles = coalesce(zipped_divide(D_warp_tiles, make_shape(CD_mma_tile_shape)), Step<_1,_1>{});



  WarpTileIteratorA<BK_dim> A_warp_tile_iter(A_smem_);


  // declare register storage for accumulators
  half acc_register[mma_tiles_per_warp_m][mma_tiles_per_warp_n][4];
  
  // A/B accumulators hold two k slices for overlap of data transfer and compute
  // each iteration of the inner loop one slice is being used for compute
  // while the next slice (mod 2) is being written to
  half A_mma_tile_reg[2][mma_tiles_per_warp_k][4];
  half B_mma_tile_reg[mma_tiles_per_warp_k][2][2];

  uint32_t(& A_mma_tile_reg_)[2][mma_tiles_per_warp_k][2] = reinterpret_cast<uint32_t(&)[2][mma_tiles_per_warp_k][2]>(A_mma_tile_reg);



  float4 A_gmem_cache_reg[4];
  float4 B_gmem_cache_reg[2];
  
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

  // copy 0th block tile from gmem -> smem
  Tensor A_block_tile = A_block_tiles(make_coord(_,_), make_coord(block_m, 0));
  Tensor B_block_tile = B_block_tiles(make_coord(_,_), make_coord(0, block_n));
  tileMemcpySwizzleUnrolled_A<BM_dim, BK_dim>(A_block_tile.data(), A_smem_, K);
  tileMemcpySwizzleUnrolled_B<BK_dim, BN_dim>(B_block_tile.data(), B_smem_, N);

  // copy 0th k slice from smem -> register
  asm volatile (
    "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
    "{%0, %1, %2, %3}, [%4];"
    : "=r"(A_mma_tile_reg_[0][0][0]), "=r"(A_mma_tile_reg_[0][0][1]), "=r"(A_mma_tile_reg_[1][0][0]), "=r"(A_mma_tile_reg_[1][0][1])
    : "r"(A_warp_tile_iter(0))
  );

  asm volatile (
    "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
    "{%0, %1, %2, %3}, [%4];"
    : "=r"(A_mma_tile_reg_[2][0][0]), "=r"(A_mma_tile_reg_[2][0][1]), "=r"(A_mma_tile_reg_[3][0][0]), "=r"(A_mma_tile_reg_[3][0][1])
    : "r"(A_warp_tile_iter(0))
  );







  // static_assert(BM_dim == 256, "BM_dim must be 256");
  for (unsigned int block_k = 1; block_k <= block_tiles_k; block_k++)
  {
    for (unsigned int mma_k = 0; mma_k < mma_tiles_per_warp_k; mma_k++)
    {
      if (block_k == 1 && thread0())
      {
        // asm volatile (
        //   "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
        //   "{%0, %1, %2, %3}, [%4];"
        //   : "=r"(A_mma_tile_reg_[0][0][0]), "=r"(A_mma_tile_reg_[0][0][1]), "=r"(A_mma_tile_reg_[1][0][0]), "=r"(A_mma_tile_reg_[1][0][1])
        //   : "r"(A_warp_tile_iter(1))
        // );
        // printf("%d, %d: %f\n", mma_k, A_warp_tile_iter(0), (float) A_mma_tile_reg[0][0][0]);
        // ++A_warp_tile_iter;

        asm volatile (
          "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
          "{%0, %1, %2, %3}, [%4];"
          : "=r"(B_mma_tile_reg_[block_row][0]), "=r"(B_mma_tile_reg_[block_row][1]), "=r"(B_mma_tile_reg_[block_row][2]), "=r"(B_mma_tile_reg_[block_row][3])
          : "r"(B_src_addr_1 + block_row * row_offset)
        );
        


      }


      // if (mma_k == mma_tiles_per_warp_k - 1)
      // {
      //   // write register -> smem
      // }

      // // load next mma k slice

      // if (mma_k == 0)
      // {
      //   // load gmem -> register
      // }

      // // compute current mma k slice
    }
  }

  half alpha_ = (half)alpha;
  half beta_ = (half)beta;
  half C_register[mma_tiles_per_warp_m][mma_tiles_per_warp_n][4];
  for (unsigned int mma_m = 0; mma_m < mma_tiles_per_warp_m; mma_m++)
  {
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        Tensor C_mma_tile = C_mma_tiles(make_coord(_,_), make_coord(mma_m, mma_n, warp_m, warp_n, block_m, block_n));
        ldmatrix_m16n8_gmem(C_mma_tile.data(), C_register[mma_m][mma_n], N * sizeof(half));
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

void kernel_10_launch(sgemm_params device_sgemm_params, KernelLogger& timer, const unsigned int num_runs = 10)
{
    
  constexpr unsigned int BM_dim = 256;
  constexpr unsigned int BN_dim = 128;
  constexpr unsigned int BK_dim = 32;
  
  constexpr unsigned int WARPS_PER_BLOCK_M = 4;
  constexpr unsigned int WARPS_PER_BLOCK_N = 2;
  constexpr unsigned int WARPS_PER_BLOCK_K = 1;

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
    constexpr unsigned int ThreadsM = WARPS_PER_BLOCK_M;
    constexpr unsigned int ThreadsN = WARP_SIZE * WARPS_PER_BLOCK_N;
    constexpr unsigned int num_threads = ThreadsM * ThreadsN;
    constexpr unsigned int shmem_bytes = (BM_dim * BK_dim + BK_dim * BN_dim) * sizeof(half);
    // constexpr unsigned int A_swizzle_bits = int_log2(BK_dim/8);
    // constexpr unsigned int B_swizzle_bits = int_log2(BN_dim/8);

    dim3 gridDim(BlocksN * BlocksM, 1);
    dim3 blockDim(ThreadsN, ThreadsM);
    
    CUDA_CHECK(cudaFuncSetAttribute(kernel_10<BM_dim, BN_dim, BK_dim, WM_dim, WN_dim, WK_dim, num_threads>,
    cudaFuncAttributeMaxDynamicSharedMemorySize,
    65536)); // set shared memory limit to 64KB which is maximum for sm_75

    for (int i = 0; i < num_runs; i++)
    {
        timer.Start();
        kernel_10
        <BM_dim, BN_dim, BK_dim,
        WM_dim, WN_dim, WK_dim, num_threads>
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

