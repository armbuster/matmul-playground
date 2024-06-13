#pragma once
#include <cuda.h>
#include <assert.h>

// load TILE_ROWS * TILE_COLS from src into dst
// assumes 1d theadblock, i.e. threadIdx.y always equals 0
// iterations is the # of times we need to iterate, passed
// as a parameter so that each thread isnt computing the same
// value. It is ceil((TILE_ROWS * TILE_COLS) / blockDim.x)
template<unsigned int TILE_ROWS,
unsigned int TILE_COLS,
typename T>
__device__ void tileMemcpy(
    T* src,
    T* dst,
    const unsigned int src_stride,
    const unsigned int dst_stride
)
{
    // assert(row_iterations * column_iterations * blockDim.x == TILE_ROWS * TILE_COLS);
    int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
    int num_threads = blockDim.x * blockDim.y;
    
    const unsigned int row_step = max(1, num_threads / TILE_COLS);
    const unsigned int col_step = num_threads;
    
    // const unsigned int column_iterations = min(1, TILE_COLS / col_step);
    // const unsigned int row_iterations = TILE_ROWS / row_step;

    const unsigned int thread_row = thread_idx / TILE_COLS;
    const unsigned int thread_col = thread_idx - (thread_row * TILE_COLS);
    
    for (unsigned int r = thread_row; r < TILE_ROWS; r+=row_step)
    {
        for (unsigned int c = thread_col; c < TILE_COLS; c+=col_step)
        {
            dst[r * dst_stride + c] =  src[r * src_stride + c];
        }
    }
    
}

__device__ __forceinline__ uint32_t cvta_to_shared_u32(const void *pointer) {
    uint32_t address;
    asm("{\n\t"
        "  .reg .u64 u64addr;\n\t"
        "  cvta.to.shared.u64 u64addr, %1;\n\t"
        "  cvt.u32.u64 %0, u64addr;\n\t"
        "}"
        : "=r"(address)
        : "l"(pointer));
    return address;
  }



__device__ __forceinline__ void ldmatrix_m16n8(
    half* shmem,
    half (&reg)[4],
    unsigned int shmem_stride_bytes
)
{
    shmem_stride_bytes /= sizeof(uint32_t);
    uint32_t (&reg_) [2] = reinterpret_cast<uint32_t(&)[2]>(reg);
    constexpr int frag_M_dim = 16;
    const unsigned int fragment_row = threadIdx.x % frag_M_dim;
    const unsigned int offset = fragment_row * shmem_stride_bytes;
    uint32_t* smem_ptr = reinterpret_cast<uint32_t*>(shmem) + offset;
    
    asm volatile (
        "ldmatrix.sync.aligned.m8n8.x2.shared.b16 "
        "{%0, %1}, [%2];"
        : "=r"(reg_[0]), "=r"(reg_[1])
        : "r"(cvta_to_shared_u32(smem_ptr))
    );
}

__device__ __forceinline__ void ldmatrix_n8k8(
    half* shmem,
    half (&reg)[2],
    unsigned int shmem_stride_bytes
)
{
    shmem_stride_bytes /= sizeof(uint32_t);
    uint32_t &reg_ = reinterpret_cast<uint32_t&>(reg);
    constexpr int frag_K_dim = 8;
    const unsigned int fragment_row = threadIdx.x % frag_K_dim;
    const unsigned int offset = fragment_row * shmem_stride_bytes;
    uint32_t* smem_ptr = reinterpret_cast<uint32_t*>(shmem) + offset;

    asm volatile (
        "ldmatrix.sync.aligned.m8n8.x1.trans.shared.b16 "
        "{%0}, [%1];"
        : "=r"(reg_)
        : "r"(cvta_to_shared_u32(smem_ptr))
    );
}

__device__ __forceinline__ void mma_sync_m16n8k8(
    half (&D)[4],
    half (&A)[4],
    half (&B)[2],
    half (&C)[4]
)
{
    uint32_t (&D_)[2] = reinterpret_cast<uint32_t(&)[2]>(D);
    uint32_t (&A_)[2] = reinterpret_cast<uint32_t(&)[2]>(A);
    uint32_t (&C_)[2] = reinterpret_cast<uint32_t(&)[2]>(C);
    uint32_t &B_ = reinterpret_cast<uint32_t&>(B);

    asm volatile (
        "mma.sync.aligned.m16n8k8.row.col.f16.f16.f16.f16 "
        "{%0, %1}, "
        "{%2, %3}, "
        "{%4}, "
        "{%5, %6};"
        : "=r"(D_[0]), "=r"(D_[1])
        : "r"(A_[0]), "r"(A_[1]),
          "r"(B_),
          "r"(C_[0]), "r"(C_[1])
    );
}

// the stmatrix ptx instruction works for sm_90 and above
// this is a workaround
__device__ __forceinline__ void stmatrix_m16n8(
    half* dst,
    half (&reg)[4],
    unsigned int dst_stride_bytes
)
{
    const unsigned int laneIdx = threadIdx.x % 32;
    uint32_t (&reg_) [2] = reinterpret_cast<uint32_t(&)[2]>(reg);
    uint32_t* dst_ptr = reinterpret_cast<uint32_t*>(dst);
    dst_stride_bytes /= sizeof(uint32_t);
    unsigned int fragment_row = laneIdx / 4;
    const unsigned int fragment_col = laneIdx % 4;
    
    // 4 adjacent threads storing 4 bytes each == 16 byte transactions
    dst_ptr[fragment_row * dst_stride_bytes + fragment_col] = reg_[0];
    fragment_row += 8;
    dst_ptr[fragment_row * dst_stride_bytes + fragment_col] = reg_[1];
}

// the stmatrix ptx instruction works for sm_90 and above
// this is a workaround
__device__ __forceinline__ void ldmatrix_m16n8_gmem(
    half* src,
    half (&reg)[4],
    unsigned int src_stride_bytes
)
{
    const unsigned int laneIdx = threadIdx.x % 32;
    uint32_t (&reg_) [2] = reinterpret_cast<uint32_t(&)[2]>(reg);
    uint32_t* src_ptr = reinterpret_cast<uint32_t*>(src);
    src_stride_bytes /= sizeof(uint32_t);
    unsigned int fragment_row = laneIdx / 4;
    const unsigned int fragment_col = laneIdx % 4;
    
    // 4 adjacent threads storing 4 bytes each == 16 byte transactions
    reg_[0] = src_ptr[fragment_row * src_stride_bytes + fragment_col];
    fragment_row += 8;
    reg_[1] = src_ptr[fragment_row * src_stride_bytes + fragment_col];
}

__device__ __forceinline__ void ldmatrix_m16n16_gmem(
    half* src,
    half (&reg)[8],
    const unsigned int src_stride_bytes
)
{
    const unsigned int laneIdx = threadIdx.x % 32;
    float4 &reg_= reinterpret_cast<float4&>(reg);
    const unsigned int src_stride_float4 = src_stride_bytes / sizeof(float4);
    const float4* src_ptr = reinterpret_cast<float4*>(src);
    // const float4* thread_ptr = src_ptr + (thread_shmem_row_map[laneIdx] * src_stride_float4) + thread_shmem_col_map[laneIdx];
    const float4* thread_ptr = src_ptr + (laneIdx * src_stride_float4) + (laneIdx / 16);
    reg_ = *thread_ptr;
}


__device__ __forceinline__ void stmatrix_m16n16_gmem(
    half* dst,
    half (&reg)[8],
    const unsigned int dst_stride_bytes
)
{
    const unsigned int laneIdx = threadIdx.x % 32;
    float4 &reg_= reinterpret_cast<float4&>(reg);
    const unsigned int dst_stride_float4 = dst_stride_bytes / sizeof(float4);
    const float4* dst_ptr = reinterpret_cast<float4*>(dst);
    // const float4* thread_ptr = dst_ptr + (thread_shmem_row_map[laneIdx] * dst_stride_float4) + thread_shmem_col_map[laneIdx];
    const float4* thread_ptr = dst_ptr + (laneIdx * dst_stride_float4) + (laneIdx / 16);
    reg_ = *thread_ptr;
}



template <unsigned int BM_dim, unsigned int BK_dim>
__device__ void tileMemcpySwizzleUnrolled_A(half* src, half* dst, const unsigned int src_stride_half)
{
    float4* src_float4 = reinterpret_cast<float4*>(src);
    float4* dst_float4 = reinterpret_cast<float4*>(dst);
    int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
    int num_threads = blockDim.x * blockDim.y;
    constexpr unsigned int BK_dim_float4 = BK_dim / 8;
    constexpr unsigned int TILE_SIZE = BM_dim * BK_dim_float4;
    const unsigned int src_stride_float4 = src_stride_half / 8;


    #pragma unroll 8
    while (thread_idx < TILE_SIZE)
    {
        const unsigned int thread_idx_y = thread_idx / BK_dim_float4;
        const unsigned int thread_idx_x = thread_idx % BK_dim_float4;
        const unsigned int src_ind = thread_idx_y * src_stride_float4 + thread_idx_x;
        unsigned int dst_ind = thread_idx_y * BK_dim_float4 + thread_idx_x;
        dst_ind = dst_ind ^ ((dst_ind & 0b10000) >> 4);
        dst_ind = dst_ind ^ ((dst_ind & 0b1100) >> 2);
        dst_float4[dst_ind] = src_float4[src_ind];
        thread_idx += num_threads;
    }
}

template <unsigned int BK_dim, unsigned int BN_dim>
__device__ void tileMemcpySwizzleUnrolled_B(half* src, half* dst, const unsigned int src_stride_half)
{
    float4* src_float4 = reinterpret_cast<float4*>(src);
    float4* dst_float4 = reinterpret_cast<float4*>(dst);
    int thread_idx = threadIdx.y * blockDim.x + threadIdx.x;
    int num_threads = blockDim.x * blockDim.y;
    constexpr unsigned int BN_dim_float4 = BN_dim / 8;
    constexpr unsigned int TILE_SIZE = BK_dim * BN_dim_float4;
    const unsigned int src_stride_float4 = src_stride_half / 8;

    #pragma unroll 8
    while (thread_idx < TILE_SIZE)
    {
        const unsigned int thread_idx_y = thread_idx / BN_dim_float4;
        const unsigned int thread_idx_x = thread_idx % BN_dim_float4;
        const unsigned int src_ind = thread_idx_y * src_stride_float4 + thread_idx_x;
        unsigned int dst_ind = thread_idx_y * BN_dim_float4 + thread_idx_x;
        dst_ind = dst_ind ^ ((dst_ind & 0b1110000) >> 4);
        dst_float4[dst_ind] = src_float4[src_ind];
        thread_idx += num_threads;
    }
}