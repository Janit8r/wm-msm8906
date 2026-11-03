#!/bin/bash
#
# 把 SimAdmin 的预编译产物装进固件的 files/ 覆盖层。
#
# 产物来源：luci-app-simadmin 仓库的滚动 Release（tag: prebuilt）
#   https://github.com/Janit8r/luci-app-simadmin/releases/download/prebuilt/simadmin-aarch64.tar.gz
#
# 包内含：simadmin 二进制（构建时已 UPX 压缩）+ www 前端。
# 本脚本只负责解包到 openwrt/files/opt/simadmin/，并在必要时补一次 UPX。
#
# 用法：bash scripts/install-simadmin-prebuilt.sh [目标 files 目录]

set -euo pipefail

URL="${SIMADMIN_PREBUILT_URL:-https://github.com/Janit8r/luci-app-simadmin/releases/download/prebuilt/simadmin-aarch64.tar.gz}"
DEST="${1:-${GITHUB_WORKSPACE:-.}/openwrt/files}"

echo "==> 下载 SimAdmin 预编译产物"
echo "    $URL"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fL --retry 3 --retry-delay 5 --connect-timeout 20 \
	-o "$TMP/simadmin.tar.gz" "$URL"

echo "==> 包内容"
tar tzf "$TMP/simadmin.tar.gz" | sed 's/^/    /' | head -20

mkdir -p "$DEST/opt/simadmin"
tar xzf "$TMP/simadmin.tar.gz" -C "$DEST/opt/simadmin"
chmod 0755 "$DEST/opt/simadmin/simadmin"
chmod 0755 "$DEST/opt/simadmin/start.sh" 2>/dev/null || true

# 二进制必须是 UPX 压缩过的：固件分区空间紧张，8.2MB -> 约 3MB
if grep -qa 'UPX!' "$DEST/opt/simadmin/simadmin"; then
	echo "==> 二进制已是 UPX 压缩"
elif command -v upx >/dev/null 2>&1; then
	echo "==> 二进制未压缩，就地 UPX 压缩"
	upx --best --lzma "$DEST/opt/simadmin/simadmin" || true
else
	echo "!! 二进制未压缩且构建环境没有 upx，跳过（体积会偏大）"
fi

echo "==> 安装结果"
ls -la "$DEST/opt/simadmin" | sed 's/^/    /'
du -sh "$DEST/opt/simadmin" 2>/dev/null | sed 's/^/    total: /'
