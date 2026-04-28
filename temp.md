# Private-State CLI UX Notes

These issues came up while using the private-state CLI on a Lambda Cloud GPU instance.

1. Amount tracking is manual. After `deposit-bridge --amount 10`, users need to remember that value for `deposit-channel --amount 10`. A `deposit-channel --all` option would better match the intent to move the full bridge-vault balance into the channel.

2. GPU/Docker readiness is not obvious from the CLI workflow. Users had to manually run `nvidia-smi` and `docker run --gpus all ... nvidia-smi`. `--doctor` should make Docker mode and GPU visibility explicit when CUDA-backed Tokamak CLI execution is expected.
