#include <cuda.h>
#include <mma.h>
#include <cute/tensor.hpp>

#include "device_utils.cuh"
#include "structs_n_stuff.cuh"
#include "cute_utils.cuh"

using namespace cute;

__device__ __forceinline__ void ldmatrix_a(
  half* src,
  half (&reg)[4][8][4],
  const unsigned int smem_stride
)
{
  uint32_t (&reg_) [4][8][2] = reinterpret_cast<uint32_t(&)[4][8][2]>(reg);
  unsigned int logical_offset = (threadIdx.x % 32) * smem_stride;
  unsigned int swizzled_offset = logical_offset ^ ((logical_offset & 0b111000000) >> 3);
  uint32_t src_addr = cvta_to_shared_u32(src + swizzled_offset);
  
  // 0
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][0][0]), "=r"(reg_[0][0][1]), "=r"(reg_[1][0][0]), "=r"(reg_[1][0][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;
  
  // 1
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][1][0]), "=r"(reg_[0][1][1]), "=r"(reg_[1][1][0]), "=r"(reg_[1][1][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;

  // 2
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][2][0]), "=r"(reg_[0][2][1]), "=r"(reg_[1][2][0]), "=r"(reg_[1][2][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 3
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][3][0]), "=r"(reg_[0][3][1]), "=r"(reg_[1][3][0]), "=r"(reg_[1][3][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b1110000;

  // 4
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][4][0]), "=r"(reg_[0][4][1]), "=r"(reg_[1][4][0]), "=r"(reg_[1][4][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 5
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][5][0]), "=r"(reg_[0][5][1]), "=r"(reg_[1][5][0]), "=r"(reg_[1][5][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;
  
  // 6
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][6][0]), "=r"(reg_[0][6][1]), "=r"(reg_[1][6][0]), "=r"(reg_[1][6][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 7
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][7][0]), "=r"(reg_[0][7][1]), "=r"(reg_[1][7][0]), "=r"(reg_[1][7][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b1000001110000;

  // 0
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][0][0]), "=r"(reg_[2][0][1]), "=r"(reg_[3][0][0]), "=r"(reg_[3][0][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;
  
  // 1
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][1][0]), "=r"(reg_[2][1][1]), "=r"(reg_[3][1][0]), "=r"(reg_[3][1][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;

  // 2
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][2][0]), "=r"(reg_[2][2][1]), "=r"(reg_[3][2][0]), "=r"(reg_[3][2][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 3
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][3][0]), "=r"(reg_[2][3][1]), "=r"(reg_[3][3][0]), "=r"(reg_[3][3][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b1110000;

  // 4
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][4][0]), "=r"(reg_[2][4][1]), "=r"(reg_[3][4][0]), "=r"(reg_[3][4][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 5
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][5][0]), "=r"(reg_[2][5][1]), "=r"(reg_[3][5][0]), "=r"(reg_[3][5][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;
  
  // 6
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][6][0]), "=r"(reg_[2][6][1]), "=r"(reg_[3][6][0]), "=r"(reg_[3][6][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 7
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[2][7][0]), "=r"(reg_[2][7][1]), "=r"(reg_[3][7][0]), "=r"(reg_[3][7][1])
      : "r"(src_addr)
  );
}



__device__ __forceinline__ void ldmatrix_b(
  half* src,
  half (&reg)[8][8][2],
  const unsigned int smem_stride,
  half alpha

)
{
  uint32_t (&reg_) [8][8] = reinterpret_cast<uint32_t(&)[8][8]>(reg);
  unsigned int logical_offset = (threadIdx.x % 32) * smem_stride;
  unsigned int swizzled_offset = logical_offset ^ ((logical_offset & 0b1111000000) >> 4);
  uint32_t src_addr = cvta_to_shared_u32(src + swizzled_offset);
  // when looking at this addr in debugger, it appears that it is just the number of bytes from the start of the shared memory

  // constexpr int x_thread = 0;
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][0]), "=r"(reg_[1][0]), "=r"(reg_[2][0]), "=r"(reg_[3][0])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;
  
  // 1
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][1]), "=r"(reg_[1][1]), "=r"(reg_[2][1]), "=r"(reg_[3][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;

  // 2
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][2]), "=r"(reg_[1][2]), "=r"(reg_[2][2]), "=r"(reg_[3][2])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 3
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][3]), "=r"(reg_[1][3]), "=r"(reg_[2][3]), "=r"(reg_[3][3])
      : "r"(src_addr)
  );
  src_addr ^= 0b1110000;

  // 4
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][4]), "=r"(reg_[1][4]), "=r"(reg_[2][4]), "=r"(reg_[3][4])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 5
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][5]), "=r"(reg_[1][5]), "=r"(reg_[2][5]), "=r"(reg_[3][5])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;
  
  // 6
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][6]), "=r"(reg_[1][6]), "=r"(reg_[2][6]), "=r"(reg_[3][6])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 7
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[0][7]), "=r"(reg_[1][7]), "=r"(reg_[2][7]), "=r"(reg_[3][7])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000001110000;

  // 0
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][0]), "=r"(reg_[5][0]), "=r"(reg_[6][0]), "=r"(reg_[7][0])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;
  
  // 1
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][1]), "=r"(reg_[5][1]), "=r"(reg_[6][1]), "=r"(reg_[7][1])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;

  // 2
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][2]), "=r"(reg_[5][2]), "=r"(reg_[6][2]), "=r"(reg_[7][2])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 3
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][3]), "=r"(reg_[5][3]), "=r"(reg_[6][3]), "=r"(reg_[7][3])
      : "r"(src_addr)
  );
  src_addr ^= 0b1110000;

  // 4
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][4]), "=r"(reg_[5][4]), "=r"(reg_[6][4]), "=r"(reg_[7][4])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 5
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][5]), "=r"(reg_[5][5]), "=r"(reg_[6][5]), "=r"(reg_[7][5])
      : "r"(src_addr)
  );
  src_addr ^= 0b110000;
  
  // 6
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][6]), "=r"(reg_[5][6]), "=r"(reg_[6][6]), "=r"(reg_[7][6])
      : "r"(src_addr)
  );
  src_addr ^= 0b10000;

  // 7
  asm volatile (
      "ldmatrix.sync.aligned.m8n8.x4.trans.shared.b16 "
      "{%0, %1, %2, %3}, [%4];"
      : "=r"(reg_[4][7]), "=r"(reg_[5][7]), "=r"(reg_[6][7]), "=r"(reg_[7][7])
      : "r"(src_addr)
  );
}

template <unsigned int BM_dim,
unsigned int BN_dim,
unsigned int BK_dim,
unsigned int WM_dim,
unsigned int WN_dim,
unsigned int WK_dim,
unsigned int A_swizzle_bits,
unsigned int B_swizzle_bits>
__global__ void
kernel_4(half* A,
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
  
  // auto A_smem_layout = composition(Swizzle<3, 3, A_swizzle_bits>{}, make_layout(A_block_tile_shape, LayoutRight{}));
  // auto B_smem_layout = composition(Swizzle<3, 3, B_swizzle_bits>{}, make_layout(B_block_tile_shape, LayoutRight{}));
  auto A_smem_layout = make_layout(A_block_tile_shape, LayoutRight{});
  auto B_smem_layout = make_layout(B_block_tile_shape, LayoutRight{});
  Tensor A_smem = make_tensor(make_smem_ptr(A_smem_), A_smem_layout);
  Tensor B_smem = make_tensor(make_smem_ptr(B_smem_), B_smem_layout);

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

  Tensor A_block_tile = A_block_tiles(make_coord(_,_), make_coord(block_m, 0));
  Tensor B_block_tile = B_block_tiles(make_coord(_,_), make_coord(0, block_n));
  tileMemcpySwizzleUnrolled<BM_dim, BK_dim, A_swizzle_bits>(A_block_tile, A_smem, K, BK_dim);
  tileMemcpySwizzleUnrolled<BK_dim, BN_dim, B_swizzle_bits>(B_block_tile, B_smem, N, BN_dim);
  

  half A_mma_tile_reg[mma_tiles_per_warp_m][mma_tiles_per_warp_k][4];
  half B_mma_tile_reg[mma_tiles_per_warp_k][mma_tiles_per_warp_n][2];
  float4 A_gmem_cache_reg[8];
  float4 B_gmem_cache_reg[4];
  static_assert(BM_dim == 256, "BM_dim must be 256");
  for (unsigned int block_k = 1; block_k <= num_block_tiles_k; block_k++)
  {

    if (block_k != num_block_tiles_k)
    {
      Tensor A_block_tile = A_block_tiles(make_coord(_,_), make_coord(block_m, block_k));
      Tensor B_block_tile = B_block_tiles(make_coord(_,_), make_coord(block_k, block_n));
      // copy tile of A from global memory to registers
      // we want these memory requests to be in flight while the mmas are being computed
      {
        constexpr unsigned int float4_cols = BK_dim / 8; // 8
        Tensor src_float4 = make_tensor(reinterpret_cast<float4*>(A_block_tile.data()), make_shape(BM_dim, float4_cols), make_stride(K / 8, 1));
        unsigned int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
        const unsigned int thread_idx_y = thread_idx / float4_cols;
        const unsigned int thread_idx_x = thread_idx % float4_cols;

        A_gmem_cache_reg[0] = src_float4(thread_idx_y, thread_idx_x);
        A_gmem_cache_reg[1] = src_float4(thread_idx_y + 32, thread_idx_x);
        A_gmem_cache_reg[2] = src_float4(thread_idx_y + 64, thread_idx_x);
        A_gmem_cache_reg[3] = src_float4(thread_idx_y + 96, thread_idx_x);
        A_gmem_cache_reg[4] = src_float4(thread_idx_y + 128, thread_idx_x);
        A_gmem_cache_reg[5] = src_float4(thread_idx_y + 160, thread_idx_x);
        A_gmem_cache_reg[6] = src_float4(thread_idx_y + 192, thread_idx_x);
        A_gmem_cache_reg[7] = src_float4(thread_idx_y + 224, thread_idx_x);
      }

      // copy tile of B from global memory to registers
      {
        constexpr unsigned int float4_cols = BN_dim / 8; // 16
        Tensor src_float4 = make_tensor(reinterpret_cast<float4*>(B_block_tile.data()), make_shape(BK_dim, float4_cols), make_stride(N / 8, 1));
        unsigned int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
        const unsigned int thread_idx_y = thread_idx / float4_cols;
        const unsigned int thread_idx_x = thread_idx % float4_cols;
        B_gmem_cache_reg[0] = src_float4(thread_idx_y, thread_idx_x);
        B_gmem_cache_reg[1] = src_float4(thread_idx_y + 16, thread_idx_x);
        B_gmem_cache_reg[2] = src_float4(thread_idx_y + 32, thread_idx_x);
        B_gmem_cache_reg[3] = src_float4(thread_idx_y + 48, thread_idx_x);
      }
    }
    ldmatrix_a(
      A_smem_ + (warp_m * WM_dim) * BK_dim,
      A_mma_tile_reg,
      BK_dim
    );
    ldmatrix_b(
      B_smem_ + (warp_n * WN_dim),
      B_mma_tile_reg,
      BN_dim,
      alpha
    );


    // outer product between tiles of a and b
    #pragma unroll
    for (unsigned int mma_k = 0; mma_k < mma_tiles_per_warp_k; mma_k++)
    {
      #pragma unroll
      for (unsigned int mma_n = 0; mma_n < mma_tiles_per_warp_n; mma_n++)
      {
        #pragma unroll
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

    __syncthreads();

    {
      constexpr unsigned int float4_cols = BK_dim / 8; // 8
      auto swizzled_layout = composition(Swizzle<3,0,A_swizzle_bits>{}, make_layout(make_shape(BM_dim, float4_cols), make_stride(BK_dim / 8, 1)));
      // auto dst_layout = make_layout(make_shape(BM_dim, float4_cols), make_stride(BK_dim / 8, 1));
      Tensor dst_float4 = make_tensor(reinterpret_cast<float4*>(A_smem.data().get()), swizzled_layout);
      unsigned int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
      unsigned int thread_idx_y = thread_idx / float4_cols;
      unsigned int thread_idx_x = thread_idx % float4_cols;
      dst_float4(thread_idx_y, thread_idx_x) = A_gmem_cache_reg[0];
      dst_float4(thread_idx_y + 32, thread_idx_x) = A_gmem_cache_reg[1];
      dst_float4(thread_idx_y + 64, thread_idx_x) = A_gmem_cache_reg[2];
      dst_float4(thread_idx_y + 96, thread_idx_x) = A_gmem_cache_reg[3];
      dst_float4(thread_idx_y + 128, thread_idx_x) = A_gmem_cache_reg[4];
      dst_float4(thread_idx_y + 160, thread_idx_x) = A_gmem_cache_reg[5];
      dst_float4(thread_idx_y + 192, thread_idx_x) = A_gmem_cache_reg[6];
      dst_float4(thread_idx_y + 224, thread_idx_x) = A_gmem_cache_reg[7];
    }

    {
      constexpr unsigned int float4_cols = BN_dim / 8; // 16
      auto swizzled_layout = composition(Swizzle<3,0,B_swizzle_bits>{}, make_layout(make_shape(BK_dim, float4_cols), make_stride(BN_dim / 8, 1)));
      // auto dst_layout = make_layout(make_shape(BK_dim, float4_cols), make_stride(BN_dim / 8, 1));
      unsigned int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
      unsigned int thread_idx_y = thread_idx / float4_cols;
      unsigned int thread_idx_x = thread_idx % float4_cols;
      Tensor dst_float4 = make_tensor(reinterpret_cast<float4*>(B_smem.data().get()), swizzled_layout);
      dst_float4(thread_idx_y, thread_idx_x) = B_gmem_cache_reg[0];
      dst_float4(thread_idx_y + 16, thread_idx_x) = B_gmem_cache_reg[1];
      dst_float4(thread_idx_y + 32, thread_idx_x) = B_gmem_cache_reg[2];
      dst_float4(thread_idx_y + 48, thread_idx_x) = B_gmem_cache_reg[3];
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

void kernel_4_launch(sgemm_params device_sgemm_params, KernelLogger& timer, const unsigned int num_runs = 10)
{
    
  constexpr unsigned int BM_dim = 256;
  constexpr unsigned int BN_dim = 128;
  constexpr unsigned int BK_dim = 64;
  
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
    const unsigned int ThreadsM = WARPS_PER_BLOCK_M;
    const unsigned int ThreadsN = WARP_SIZE * WARPS_PER_BLOCK_N;
    const unsigned int shmem_bytes = (BM_dim * BK_dim + BK_dim * BN_dim) * sizeof(half);
    constexpr unsigned int A_swizzle_bits = int_log2(BK_dim/8);
    constexpr unsigned int B_swizzle_bits = int_log2(BN_dim/8);

    dim3 gridDim(BlocksN * BlocksM, 1);
    dim3 blockDim(ThreadsN, ThreadsM);
    
    CUDA_CHECK(cudaFuncSetAttribute(kernel_4<BM_dim, BN_dim, BK_dim, WM_dim, WN_dim, WK_dim, A_swizzle_bits, B_swizzle_bits>,
    cudaFuncAttributeMaxDynamicSharedMemorySize,
    65536)); // set shared memory limit to 64KB which is maximum for sm_75

    for (int i = 0; i < num_runs; i++)
    {
        timer.Start();
        kernel_4
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


