# GEMINI.md

This file describes the project structure, conventions, and guidance for AI agents
(and human contributors) working on llamabox.

---

## Project Overview

**llamabox** is a Davincibox-style project that streamlines building and running
[llama.cpp](https://github.com/ggml-org/llama.cpp) on Linux using
[Distrobox](https://github.com/89luca89/distrobox). It is primarily aimed at users
of immutable/atomic Linux distributions (Fedora Silverblue, Bazzite, etc.) where
installing GPU compute toolkits on the host is undesirable, but it works on any
distro that supports Distrobox.

The project produces four container image variants, one per GPU backend:

| Variant | Image tag | Backend |
|---------|-----------|---------|
| Vulkan | `llamabox:vulkan` | Vulkan (universal fallback) |
| NVIDIA | `llamabox:cuda` | CUDA via NVCC |
| AMD | `llamabox:rocm` | ROCm / HIP |
| Intel | `llamabox:sycl` | oneAPI SYCL / DPC++ |

All images are Fedora Linux-based and hosted on `ghcr.io`.


---

## Repository Structure

```
llamabox/
├── Containerfile.vulkan       # Vulkan build environment (universal fallback)
├── Containerfile.cuda         # NVIDIA CUDA build environment
├── Containerfile.rocm         # AMD ROCm build environment
├── Containerfile.sycl         # Intel oneAPI SYCL build environment
├── setup.sh                   # Host-side setup script (GPU detection + container creation)
├── scripts/
│   ├── build-llama.sh         # Build script baked into all images at /usr/bin/build-llama
│   ├── build-llama-vulkan.sh  # Vulkan-specific build flags
│   ├── build-llama-cuda.sh    # CUDA-specific build flags
│   ├── build-llama-rocm.sh    # ROCm-specific build flags
│   └── build-llama-sycl.sh    # SYCL-specific build flags (sources oneAPI env)
├── .github/
│   └── workflows/
│       └── build.yml          # Builds and pushes all four image variants to ghcr.io
└── README.md
```

---

## Containerfiles

### Base Conventions

- Images use a recent stable Fedora release that is compatible with the required GPU toolkit and vendor repositories. Agents should use
web search to identify recent stable Fedora releases instead of relying on their knowledge bases. If you pick a version that's
not the latest, document why.
- Each `RUN` layer should be as consolidated as possible: install packages, clean
  the dnf cache (`dnf clean all`), and copy scripts all in as few
  layers as practical to keep image size down.
- The build helper script must be copied to `/usr/bin/build-llama` and made
  executable inside the image.
- Do **not** run `dnf update` (full upgrade) in CI — pin the base image digest
  in `build.yml` if reproducibility matters, otherwise accept rolling updates.
- **Build Isolation**: To prevent host pollution and cache poisoning when switching
  between GPU backends, the build script uses variant-specific build directories
  in the user's home (e.g., `~/llama.cpp/build-cuda`, `~/llama.cpp/build-rocm`).

### Package Naming

Use official Fedora repo package names where possible. For CUDA and SYCL, use
the respective vendor repositories.

### GPU-Specific Notes

- **Vulkan**: Requires `vulkan-loader-devel`, `vulkan-headers`, and `glslc` (from the `glslc` package) along with `libshaderc-devel`. No vendor-specific driver libraries are needed in the image — Distrobox passes `/dev/dri` through from the host.
- **CUDA**: Requires `cuda-toolkit` from the NVIDIA Fedora repository. Do not bundle NVIDIA driver libraries — Distrobox passes these through from the host.
- **ROCm**: Use `rocm-hip` and `rocm-runtime` from the official Fedora repos. `ROCM_PATH` should be set to `/usr` in the image environment.
- **SYCL**: `intel-oneapi-compiler-dpcpp-cpp` and `intel-oneapi-mkl` from the Intel repository. The build script must source `/opt/intel/oneapi/setvars.sh` before invoking CMake. The DPC++ compilers `icx`/`icpx` must be used instead of GCC.

---

## setup.sh

`setup.sh` is the primary user-facing script. It runs on the **host**, not inside
the container.

### Responsibilities

1. Check that `distrobox`, `podman`, and `lshw` are available; print a friendly
   error and exit if not.
2. Detect the GPU vendor using `lshw -C display` and select the appropriate image
   tag (`cuda`, `rocm`, `sycl`, or `vulkan` as fallback).
3. Handle the case where Intel integrated graphics is present alongside a discrete
   AMD or NVIDIA GPU — prefer the discrete card. Allow the user to override with
   a `--backend` flag.
4. Create the Distrobox container:
   ```bash
   distrobox create --name llamabox --image ghcr.io/yourname/llamabox:$BACKEND --yes
   ```
5. Run the build inside the container:
   ```bash
   distrobox enter llamabox -- /usr/bin/build-llama
   ```
6. Export the built binaries to the host via `distrobox-export`:
   ```bash
   distrobox enter llamabox -- distrobox-export --bin /usr/local/bin/llama-cli
   ```
7. Support `setup.sh remove` and `setup.sh upgrade` subcommands, mirroring
   Davincibox's approach.

### Exit Codes

- `0` — success
- `1` — missing dependency
- `2` — GPU detection failed / unknown hardware
- `3` — container creation or build failed

---

## build-llama.sh Scripts

These scripts live inside the container at `/usr/bin/build-llama`. They are
responsible for cloning or updating llama.cpp and running the CMake build.

### Shared Logic (all variants)

```bash
LLAMA_DIR="$HOME/llama.cpp"

if [ ! -d "$LLAMA_DIR" ]; then
    git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

cd "$LLAMA_DIR" && git pull
```

After cloning/updating, each variant script runs its own CMake invocation (see
below) and then symlinks built binaries to `/usr/local/bin/`.

### CMake Flags per Variant

| Variant | Key flags |
|---------|-----------|
| `vulkan` | `-DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release` |
| `cuda` | `-DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler -D__NV_NO_HOST_COMPILER_CHECK=1"` |

The `cuda` variant requires explicit environment variable exports (`CUDA_PATH`, `PATH`, `CUDACXX`) in the build script to prevent host leakage from Distrobox and ensure `nvcc` is found at `/usr/local/cuda/bin/nvcc`.
| `rocm` | `-DGGML_HIPBLAS=ON -DCMAKE_BUILD_TYPE=Release` |
| `sycl` | `-DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_BUILD_TYPE=Release` |

Always pass `-j$(nproc)` to `cmake --build`.

---

## GitHub Actions (build.yml)

The workflow builds and pushes all four image variants on every push to `main`
and on a weekly schedule (to pick up upstream Arch package updates).

- Use a matrix strategy over `[vulkan, rocm, cuda, sycl]`.
- Authenticate to `ghcr.io` using `GITHUB_TOKEN` — no extra secrets needed.
- Tag images as both `:$variant` and `:$variant-$sha` for traceability.
- The `sycl` job should be expected to take significantly longer and may need a
  larger runner due to the oneAPI package size.

---

## Conventions for Contributors and Agents

### Making Changes to Containerfiles

- Always test a changed `Containerfile` locally with `podman build` before
  pushing. A build that fails in CI wastes time.
- If you add a new package, document why it is needed in a comment on the same
  `RUN` line.
- Do not install packages that are only needed at runtime if Distrobox already
  provides them via host passthrough (e.g., NVIDIA userspace drivers).

### Making Changes to setup.sh

- `setup.sh` must remain POSIX-compatible (`#!/usr/bin/env bash` is fine, but
  avoid bashisms that break on older bash versions shipped by some distros).
- GPU detection logic lives in a single `detect_gpu()` function. Keep all
  detection logic there — do not scatter `lshw` calls elsewhere in the script.
- Always test the `--backend` override flag when changing detection logic.

### Making Changes to build-llama Scripts

- The scripts are baked into the image at build time. A change here requires
  rebuilding and pushing the image before it takes effect for users.
- Keep the clone/update logic identical across all four variants to avoid drift.
  If you need to change it, change it in all four (or refactor into a shared
  sourced snippet).
- Do not hardcode the llama.cpp version or commit. Always build from the latest
  `HEAD` of the default branch so users get current GGUF and model support.

### What Agents Should Not Do

- Do not modify `setup.sh` to require Docker instead of Podman. Podman's
  rootless model is the reason Distrobox works cleanly on atomic distros.
- Do not add GUI components, desktop launchers, or `.desktop` files. llamabox
  is a CLI tool — llama.cpp binaries are invoked from the terminal.
- Do not pin llama.cpp to a specific release tag in the build scripts without
  a corresponding issue or user request documenting why.
- Do not add a fifth image variant without first opening an issue to discuss
  the GPU backend and verifying that llama.cpp's CMake supports it cleanly.

---

## Testing

There is currently no automated test suite for the built binaries. Manual testing
checklist after any change:

1. `setup.sh` runs cleanly on a fresh system with no existing `llamabox` container.
2. `setup.sh remove` cleanly removes the container and exported binaries.
3. `setup.sh upgrade` recreates the container and rebuilds without residual state.
4. `llama-cli` is callable from the host shell after setup (verify `distrobox-export` worked).
5. A small GGUF model (e.g., a quantized Qwen or Llama 3.2 1B) runs without errors.
6. GPU utilisation is visible in `nvtop`/`radeontop`/`intel_gpu_top` during inference
   for the respective GPU variant. For Vulkan, confirm device selection with
   `vulkaninfo` inside the container.

---

## Useful References

- [llama.cpp CMake build docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [Distrobox documentation](https://distrobox.it/)
- [davincibox](https://github.com/zelikos/davincibox) — the inspiration for this project
- [NVIDIA CUDA Repository for Fedora](https://developer.download.nvidia.com/compute/cuda/repos/fedora/)
- [Fedora ROCm documentation](https://fedoraproject.org/wiki/SIGs/HC)
- [Intel oneAPI Yum Repository](https://yum.repos.intel.com/oneapi)

Your contribution is very much appreciated. Thank you for your help!
