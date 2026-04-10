#!/bin/bash
# ======================================================
#  rebuild_fdp_kernel.sh
#  간단한 FDP 커널 재빌드 + 설치 자동화 스크립트
# ======================================================

set -e  # 중간에 에러 나면 즉시 종료

SRC=/mnt/mysql_8/QEMU/linux_6.8.0-78/linux-noble
BUILD=/mnt/mysql_8/QEMU/build-server
LOCALVER=-fdp
echo "[0] 기존 FDP .deb 정리 - 최신 1개만 보존"

# 정리 대상 패턴 목록
PATTERNS=(
  "linux-image-6.8.12-fdp_*.deb"
  "linux-image-6.8.12-fdp-dbg_*.deb"
  "linux-headers-6.8.12-fdp_*.deb"
  "linux-libc-dev_6.8.12-ga54f3bbd24a2-*_amd64.deb"
  "linux-upstream_6.8.12-ga54f3bbd24a2-*_amd64.buildinfo"
  "linux-upstream_6.8.12-ga54f3bbd24a2-*_amd64.changes"
)

for pat in "${PATTERNS[@]}"; do
    # 패턴에 매칭되는 파일 목록 (없으면 그냥 넘어감)
    matches=$(ls $pat 2>/dev/null || true)
    [ -z "$matches" ] && continue

    # 버전 순 정렬해서 마지막(가장 최신) 하나만 남김
    newest=$(printf '%s\n' $matches | sort -V | tail -n1)
    olds=$(printf '%s\n' $matches | grep -v "^$newest\$" || true)

    echo "== 패턴: $pat"
    echo "  보존: $newest"

    if [ -n "$olds" ]; then
        echo "  삭제:"
        printf '    %s\n' $olds
        printf '%s\n' $olds | xargs -r rm -v
    else
        echo "  삭제할 파일 없음 (1개뿐)"
    fi

    echo
done

echo "[1] 빌드 환경 설정"
export KBUILD_OUTPUT=$BUILD
cd $SRC

echo "[2] 커널 빌드 시작..."
make -j"$(nproc)"

echo "[3] .deb 패키지 생성..."
make -j"$(nproc)" bindeb-pkg LOCALVERSION=$LOCALVER

echo "[4] .deb 설치..."
cd /mnt/mysql_8/QEMU
IMG_DEB=$(ls -1t linux-image-6.8.*${LOCALVER}_*.deb | head -n1)
HDR_DEB=$(ls -1t linux-headers-6.8.*${LOCALVER}_*.deb | head -n1)

sudo dpkg -i "$IMG_DEB" "$HDR_DEB"

echo "[5] GRUB 갱신..."
sudo update-grub

echo "[6] 빌드 완료 ✅"
echo "-------------------------------------------"
echo "패키지: $IMG_DEB"
echo "버전 확인은: uname -r (재부팅 후)"
echo "-------------------------------------------"
echo "지금 바로 재부팅할까요? (y/n)"
read ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    sudo reboot
else
    echo "재부팅은 나중에 직접 해주세요."
fi

