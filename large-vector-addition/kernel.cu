#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>

#define SIZE 1024LL*1024LL * 256LL
#define CHUNK_SIZE 1024LL*1024LL * 64LL


__global__ void add(int* a, int* b, int* c, int n) {
	int idx = blockIdx.x * blockDim.x + threadIdx.x;
	if (idx < n) {
		c[idx] = a[idx] + b[idx];
	}
		
	
}

void rand_ints(int* ptr, int size) {
	for (int i = 0; i < size; i++) {
		ptr[i] = rand();
	}
}

int main(int argc, char** argv) {

	if (argc != 2) {
		printf("Usage: %s <threads_per_block>\n", argv[0]);
		return 1;
	}
	int threads = atoi(argv[1]);

	if (threads < 32 || threads > 1024) {
		printf("Error: Threads per block must be between 32 and 1024.\n");
		return 1;
	}

	int *chunk_a, * chunk_b, * chunk_c;
	int* d_a, * d_b, * d_c;
	chunk_a = (int*)malloc(CHUNK_SIZE * sizeof(int));
	chunk_b = (int*)malloc(CHUNK_SIZE * sizeof(int));
	chunk_c = (int*)malloc(CHUNK_SIZE * sizeof(int));


	cudaMalloc((void**)&d_a, SIZE * sizeof(int));
	cudaMalloc((void**)&d_b, SIZE * sizeof(int));
	cudaMalloc((void**)&d_c, SIZE * sizeof(int));

	rand_ints(chunk_a, CHUNK_SIZE);
	rand_ints(chunk_b, CHUNK_SIZE);

	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);

	float total_kernel_time_ms = 0.0f;

	for (long long offset = 0; offset < SIZE; offset += CHUNK_SIZE) {
		
		long long transfer_size = (SIZE - offset) >= CHUNK_SIZE ? CHUNK_SIZE : SIZE - offset;
		size_t transfer_size_bytes = transfer_size * sizeof(int);



		cudaMemcpy(d_a + offset, chunk_a, transfer_size_bytes, cudaMemcpyHostToDevice);
		cudaMemcpy(d_b + offset, chunk_b, transfer_size_bytes, cudaMemcpyHostToDevice);

		long long blocks = (transfer_size + threads - 1) / threads;

		cudaEventRecord(start);

		add << <blocks, threads >> > (d_a + offset, d_b + offset, d_c + offset, transfer_size);

		cudaEventRecord(stop);
		cudaEventSynchronize(stop);

		float milliseconds = 0;
		cudaEventElapsedTime(&milliseconds, start, stop);
		total_kernel_time_ms += milliseconds;
		

		cudaMemcpy(chunk_c, d_c + offset, transfer_size_bytes, cudaMemcpyDeviceToHost);

	}

	printf("%13d | %22.3f ms\n", threads, total_kernel_time_ms);

	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	cudaFree(d_a);
	cudaFree(d_b);
	cudaFree(d_c);
	free(chunk_a);
	free(chunk_b);
	free(chunk_c);

	return 0;

}