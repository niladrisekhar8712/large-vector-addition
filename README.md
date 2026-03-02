# Massive CUDA Vector Addition (Out-of-Core Processing)

## Overview
This project adds two massive integer vectors of 256 million elements each ($256 \times 10^6$). Storing both input vectors and the output vector simultaneously on the GPU would require **3 GB of continuous VRAM**. 

While a 3 GB allocation might technically fit on an empty 4 GB NVIDIA GTX 1650, Windows and display drivers typically reserve a significant portion of VRAM, making a single massive allocation highly prone to Out-Of-Memory (OOM) crashes. To bypass these hardware limitations and make the program infinitely scalable, we implemented an "out-of-core" chunking strategy, processing the data in smaller chunks to keep the GPU VRAM footprint strictly under 1 GB.

## The Architecture
1. **Host (CPU) Chunking:** We allocate 64-million-element chunks (256 MB per array) in CPU RAM.
2. **Device (GPU) Reuse:** Instead of allocating the full 3 GB on the GPU, we allocate only enough VRAM to hold one chunk at a time (~768 MB total for arrays `a`, `b`, and `c`).
3. **Sequential Processing:** We loop through the 256-million-element workload, transferring and computing one chunk at a time, reusing the exact same device pointers for every pass.



## Key Learnings & Classic Bugs Squashed
Throughout the development of this benchmark, we encountered and solved several classic CUDA pitfalls:

* **The `cudaMalloc` Pointer Trap:** `cudaMalloc` returns an error code, not a memory address. Assigning its return value directly (e.g., `d_a = (int*)cudaMalloc(...)`) overwrites the device pointer with `0` and causes a segmentation fault on the first `cudaMemcpy`.
* **Preventing 32-bit Integer Overflows:** When calculating memory sizes in bytes for hundreds of millions of elements, the byte count easily exceeds the 2.14 billion limit of a standard 32-bit signed integer. We secured the math by enforcing 64-bit arithmetic using the `LL` suffix in our macros (e.g., `1024LL`).
* **The `blockDim.x` Illusion:** When dynamically testing different thread block sizes (32, 64, 128) via the command line, leaving a hardcoded `THREADS_PER_BLOCK` macro inside the kernel's index calculation (`idx = blockIdx.x * 256 + threadIdx.x`) caused the GPU to skip mathematical operations and report artificially fast (but completely incorrect) execution times. 
* **Benchmarking Noise (CPU Starvation):** Calling a slow, single-threaded CPU function like `rand()` inside the benchmarking loop to generate 128 million numbers caused the GPU to idle for so long that it dropped into a low-power sleep state. We fixed this by moving data generation outside the timing loop and adding a GPU "warm-up" kernel.
* **Debug Mode:** Visual Studio compiles in **Debug mode** by default, which disables GPU optimizations and forces variables into slow local memory. True performance profiling must always be done in **Release mode (x64)**.

---

## How to Run the Benchmark
Open your terminal, navigate to the folder, and execute the script using the following command. This automatically bypasses the default Windows PowerShell execution policy for this single run, preventing security block errors:
```PowerShell
powershell.exe -ExecutionPolicy Bypass -File .\run_benchmark.ps1
```
## Benchmarking Results (GTX 1650)

During the profiling of this code on an NVIDIA GTX 1650 (4GB VRAM), we observed how different bottlenecks can heavily distort GPU performance metrics.

### 1. The "Sawtooth" Anomaly (CPU Starvation & Debug Mode)
Before applying the final optimizations, the benchmark produced the following erratic results:

| Threads/Block | Total Kernel Time (ms) |
|--------------:|-----------------------:|
| 32            | 44.774 ms              |
| 64            | 50.570 ms              |
| 128           | 128.144 ms             |
| 256           | 57.895 ms              |
| 512           | 154.131 ms             |
| 1024          | 221.533 ms             |

**Why this happened:** This massive fluctuation (jumping from 50ms up to 128ms, back down to 57ms) was caused by a mix of **Debug mode** compilation and **CPU starvation**. The slow, single-threaded `rand()` function on the CPU was taking so long to generate the next 64-million-element chunk that the GTX 1650 dropped into a low-power sleep state between kernel launches. 

### 2. Final Optimized Performance
After compiling in **Release mode (x64)**, separating the CPU data generation from the timing loop, and adding a GPU warm-up launch, the GTX 1650 revealed its true performance curve:

| Threads/Block | Total Kernel Time (ms) | Notes |
|--------------:|-----------------------:|:------|
| 32            | 32.655 ms              | Suboptimal occupancy; SMs cannot hide memory latency. |
| 64            | 18.444 ms              | Hardware sweet spot reached. |
| 128           | 18.407 ms              | Memory-bound limit reached (~162 GB/s bandwidth). |
| 256           | 18.669 ms              | Standard recommended configuration. |
| 512           | 18.534 ms              | Memory-bound limit maintained. |
| 1024          | 18.449 ms              | Maximum hardware limit for Turing architecture. |

**Conclusion:** The kernel is strictly **Memory-Bound**. The 896 CUDA cores on the GTX 1650 compute the addition much faster than the VRAM can supply the data. The flatline at ~18.5ms represents the card's physical memory bandwidth limit (achieving ~162 GB/s out of the theoretical 192 GB/s maximum).
