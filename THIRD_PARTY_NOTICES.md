# Third-party runtime notices

The Android application bundles the following ARM64 runtime files for the
optional built-in Linux Runtime:

- PRoot `5.1.107.92`, from the Termux package repository:
  https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.92_aarch64.deb
- libtalloc `2.4.3`, from the Termux package repository:
  https://packages.termux.dev/apt/termux-main/pool/main/libt/libtalloc/libtalloc_2.4.3_aarch64.deb
- libandroid-shmem `0.7`, from the Termux package repository:
  https://packages.termux.dev/apt/termux-main/pool/main/l/libandroid-shmem/libandroid-shmem_0.7_aarch64.deb
- Alpine Linux minirootfs `3.22.5` for `aarch64`:
  https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.5-aarch64.tar.gz

The exact asset hashes are recorded in the source tree and the Flutter adapter
verifies the Alpine rootfs SHA-256 before installation. The upstream package
license and copyright files remain available from the linked package sources;
the Alpine rootfs also contains software distributed under the licenses of its
individual Alpine packages. This notice does not replace those upstream terms.
