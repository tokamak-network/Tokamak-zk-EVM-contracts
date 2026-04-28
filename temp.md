# Private-State CLI UX Notes

These issues came up while using the private-state CLI on a Lambda Cloud GPU instance.

1. GPU/Docker readiness is not obvious from the CLI workflow. Users had to manually run `nvidia-smi` and `docker run --gpus all ... nvidia-smi`. `--doctor` should make Docker mode and GPU visibility explicit when CUDA-backed Tokamak CLI execution is expected.
