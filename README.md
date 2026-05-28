# llamabox 🦙📦

**llamabox** is a [Davincibox](https://github.com/zelikos/davincibox)-style project designed to streamline the building and execution of [llama.cpp](https://github.com/ggml-org/llama.cpp) on Linux using [Distrobox](https://github.com/89luca89/distrobox).

It is primarily intended for use with **immutable/atomic Linux distributions** (such as Fedora Silverblue, Bazzite, or openSUSE Aeon) where installing complex GPU compute toolkits (CUDA, ROCm, etc.) directly on the host system is undesirable or difficult.

## Features

- **Isolated Build Environment:** Keep your host system clean by building `llama.cpp` inside a dedicated container.
- **GPU Acceleration:** Pre-configured images for major GPU backends (NVIDIA, AMD, Intel, and Vulkan).
- **Host Integration:** Built binaries are exported directly to your host's `$HOME/.local/bin` for easy access.
- **Automated Setup:** Single-script setup that detects your hardware and configures everything.

## Supported Variants

llamabox provides four container image variants, one for each major GPU backend:

| Backend | Image Tag | Target Hardware |
|---------|-----------|-----------------|
| **NVIDIA** | `cuda` | NVIDIA GPUs (via CUDA) |
| **AMD** | `rocm` | AMD GPUs (via ROCm/HIP) |
| **Intel** | `sycl` | Intel GPUs (via oneAPI SYCL) |
| **Vulkan** | `vulkan` | Universal fallback for any GPU with Vulkan support |

## Prerequisites

Ensure you have the following installed on your host machine:

- [Distrobox](https://github.com/89luca89/distrobox)
- A container engine: [Podman](https://podman.io/) (recommended) or [Docker](https://www.docker.com/)
- `lshw` (used for GPU detection)

## Quick Start

Run this on your host machine:

```bash
curl -sSL https://raw.githubusercontent.com/mienaiKnife/llamabox/main/setup.sh | bash
```

This will:
1. Detect your GPU hardware.
2. Pull the appropriate container image.
3. Clone and build the latest `llama.cpp`.
4. Export `llama-cli` and `llama-server` to `~/.local/bin/`.

## Usage

Once installed, you can run `llama.cpp` binaries directly from your host terminal:

```bash
# Run a model (assuming it's in your current directory)
llama-cli -m my-model.gguf -p "The meaning of life is" -n 128

# Start the server
llama-server -m my-model.gguf --port 8080
```

> **Note:** Ensure `~/.local/bin` is in your `$PATH`.

### Advanced Setup Options

The `setup.sh` script supports several subcommands and flags:

- **Manual Backend Selection:** If you want to force a specific backend (e.g., using Vulkan on an NVIDIA card):
  ```bash
  ./setup.sh --backend vulkan
  ```
- **Home Source Directory:** By default, `llamabox` builds `llama.cpp` inside the container at `/opt/llama.cpp` to keep your home directory clean. If you want to persist the source code and build cache across container removals or upgrades, you can opt to build in your home directory instead:
  ```bash
  ./setup.sh --home-source
  ```
- **Upgrade:** Re-pull the image and rebuild `llama.cpp` to get the latest updates:
  ```bash
  ./setup.sh upgrade
  ```
- **Removal:** Delete the container and the exported binaries:
  ```bash
  ./setup.sh remove
  ```

## Disclaimer

This is a vibecoded project. The NVIDIA backend is currently the primary testing target. **ROCm (AMD) and SYCL (Intel) installations are currently untested.** If you encounter issues or have successfully used these backends, please [open an issue](https://github.com/mienaiKnife/llamabox/issues).

## Development

For detailed architecture information, repository structure, and contribution guidelines, please refer to [GEMINI.md](GEMINI.md).
