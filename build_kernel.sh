#!/usr/bin/env bash
# build_kernel_o.sh — Out-of-tree Linux build helper for QEMU boot
# 사용법:
#   ./build_kernel_o.sh                  # bzImage + modules 빌드
#   INSTALL_MODS=1 ROOT_IMG=root.qcow2 ./build_kernel_o.sh   # 모듈을 VM 루트에 설치까지
# 선택: LOCALVERSION=-fdp-$(date +%m%d-%H%M) 처럼 외부에서 덮어쓰기 가능

set -euo pipefail

SRCDIR="${SRCDIR:-/mnt/mysql_8/QEMU/linux_6.8.0-78/linux-noble}"
BUILDDIR="${BUILDDIR:-/mnt/mysql_8/QEMU/build-linux-6.8-fdp}"
LOCALVERSION="${LOCALVERSION:--fdp-test}"
# SRCDIR="${SRCDIR:-/mnt/mysql_8/QEMU/linux_origin/linux-noble}"
# BUILDDIR="${BUILDDIR:-/mnt/mysql_8/QEMU/build-linux-6.8-origin}"
# LOCALVERSION="${LOCALVERSION:--origin}"
INSTALL_MODS="${INSTALL_MODS:-0}"      # 1로 주면 모듈 루트 이미지에 설치
ROOT_IMG="${ROOT_IMG:-}"               # INSTALL_MODS=1일 때 root.qcow2 경로

# 0) 준비
mkdir -p "$BUILDDIR"

# 1) .config 준비 (최초 1회만)
if [[ ! -f "$BUILDDIR/.config" ]]; then
  cp -v "/boot/config-$(uname -r)" "$BUILDDIR/.config"
  yes "" | make -C "$SRCDIR" O="$BUILDDIR" olddefconfig
fi

# 2) 헤드리스/QEMU 부팅을 위한 필수 빌트인 보정
#    (=y 권장: 시리얼 콘솔/장치노드/부팅 디스크/네트워크)
"$SRCDIR"/scripts/config --file "$BUILDDIR/.config" \
  --enable CONFIG_DEVTMPFS \
  --enable CONFIG_DEVTMPFS_MOUNT \
  --enable CONFIG_SERIAL_8250 \
  --enable CONFIG_SERIAL_8250_CONSOLE \
  --enable CONFIG_VIRTIO_PCI \
  --enable CONFIG_VIRTIO_BLK \
  --enable CONFIG_EXT4_FS \
  --enable CONFIG_NET \
  --enable CONFIG_VIRTIO_NET \
  --enable CONFIG_KVM_GUEST \
  --set-str SYSTEM_TRUSTED_KEYS "" \
  --set-str SYSTEM_REVOCATION_KEYS "" \
  --disable MODULE_SIG \
  --disable SYSTEM_BLACKLIST_KEYRING

# NVMe 경로를 테스트하려면(부팅 디스크가 아니어도 OK)
"$SRCDIR"/scripts/config --file "$BUILDDIR/.config" \
  --enable CONFIG_BLK_DEV_NVME \
  --enable CONFIG_NVME_CORE

# (여기 네 FDP/EXT4 실험용 Kconfig가 있다면 동일하게 enable)

# 새로 켠 옵션들 기본값 채우기
make -C "$SRCDIR" O="$BUILDDIR" olddefconfig

# 3) 빌드
export LOCALVERSION
echo "[build] LOCALVERSION=${LOCALVERSION}"
make -C "$SRCDIR" O="$BUILDDIR" -j"$(nproc)" bzImage modules
#make -C "/mnt/mysql_8/QEMU/linux_6.8.0-78/linux-noble" O="/mnt/mysql_8/QEMU/build-linux-6.8-fdp" -j$(nproc) bzImage
#make -C "/mnt/mysql_8/QEMU/linux_origin/linux-noble" O="/mnt/mysql_8/QEMU/build-linux-6.8-origin" -j$(nproc) bzImage


# 4) 커널 버전/경로 출력
KVER="$(make -s -C "$SRCDIR" O="$BUILDDIR" kernelrelease)"
BZ="$BUILDDIR/arch/x86/boot/bzImage"
echo "[done] kernelrelease=${KVER}"
echo "[done] bzImage=${BZ}"

# 5) (옵션) 루트 이미지에 모듈 설치
if [[ "$INSTALL_MODS" == "1" ]]; then
  if [[ -z "$ROOT_IMG" ]]; then
    echo "[error] INSTALL_MODS=1 인데 ROOT_IMG 경로가 비어있음"
    exit 1
  fi
  echo "[mods] installing modules into ${ROOT_IMG} ..."
  sudo modprobe nbd max_part=8
  sudo qemu-nbd -c /dev/nbd0 "$ROOT_IMG"
  sudo partprobe /dev/nbd0
  # 파티션이 1개라고 가정: 필요 시 lsblk로 확인하여 조정
  sudo mount /dev/nbd0p1 /mnt/vmroot
  sudo make -C "$SRCDIR" O="$BUILDDIR" modules_install INSTALL_MOD_PATH=/mnt/vmroot
  sudo depmod -b /mnt/vmroot "$KVER"
  sudo umount /mnt/vmroot
  sudo qemu-nbd -d /dev/nbd0
  echo "[mods] installed to /lib/modules/${KVER} in ${ROOT_IMG}"
fi

cat <<EOF

== 다음 단계 ==
QEMU로 부팅:
  qemu-system-x86_64 \\
    -enable-kvm -cpu host -smp 4 -m 8G \\
    -nographic -serial mon:stdio \\
    -kernel "$BZ" \\
    -append "console=ttyS0 root=LABEL=cloudimg-rootfs rw" \\
    -drive file=root.qcow2,if=virtio,format=qcow2 \\
    -cdrom seed.iso \\
    -device virtio-net-pci,netdev=n1 \\
    -netdev user,id=n1,hostfwd=tcp::2222-:22

VM에서 확인:
  uname -r      # ${KVER} 이어야 정상
EOF
