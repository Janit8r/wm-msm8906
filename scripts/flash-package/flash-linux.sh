#!/bin/bash
#
# WF2 / UFI-W-001 (QRZL903, msm8916) OpenWrt 刷机脚本 —— Linux / macOS
#
# 需要系统里已安装 adb / fastboot（Debian/Ubuntu: apt install android-sdk-platform-tools
# 或 apt install adb fastboot；macOS: brew install android-platform-tools）
#
# 流程和 flash-windows.bat 完全一致：
#   1. 切 fastboot，刷 lk2nd 临时引导
#   2. 备份 modem 校准分区 fsc / fsg / modemst1 / modemst2
#   3. 重写 GPT（原厂布局和 OpenWrt 完全不同）
#   4. 刷 bootloader
#   5. 回填校准分区到新位置（不做这步刷完没信号）
#   6. 刷 boot.img / rootfs.img

set -u
cd "$(dirname "$0")" || exit 1

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; NC=$'\033[0m'
say()  { echo "$*"; }
ok()   { echo "${GRN}$*${NC}"; }
warn() { echo "${YEL}$*${NC}"; }
die()  { echo "${RED}$*${NC}"; exit 1; }

echo "============================================================"
echo "  WF2 / UFI-W-001 (QRZL903, msm8916)  OpenWrt 一键刷机"
echo "  适用于「Android 原厂系统」的设备"
echo "============================================================"
echo
echo "会做：刷 lk2nd -> 备份 modem 校准 -> 重写 GPT -> 刷 bootloader"
echo "      -> 回填校准 -> 刷 boot.img / rootfs.img"
echo
warn "[警告] 会清空设备上的原厂 Android 和所有数据，不可恢复。"
echo
read -r -p "确认继续？输入 yes 回车: " ans
[ "$ans" = "yes" ] || { say "已取消。"; exit 0; }
echo

# ---------- 0. 检查 ----------
for f in boot.img rootfs.img lk2nd.img gpt_both0-fixed.bin \
         aboot.bin hyp.mbn rpm.mbn sbl1.mbn tz.mbn sbc_1.0_8016.bin; do
	[ -f "$f" ] || die "[错误] 缺少文件: $f（请确认压缩包已完整解压）"
done
command -v adb      >/dev/null 2>&1 || die "[错误] 找不到 adb，请先安装 android-tools"
command -v fastboot >/dev/null 2>&1 || die "[错误] 找不到 fastboot，请先安装 android-tools"

wait_fastboot() {
	local n=0 max="${1:-90}"
	while [ "$n" -lt "$max" ]; do
		if fastboot devices 2>/dev/null | grep -q fastboot; then
			return 0
		fi
		n=$((n + 1))
		sleep 1
	done
	return 1
}

fb() {
	fastboot "$@" || die "[错误] fastboot $* 失败"
}

dump_part() {
	local p="$1"
	say "      备份 $p ..."
	fastboot oem dump "$p" >/dev/null 2>&1 || {
		die "[错误] 设备不支持 fastboot oem dump $p
        没有校准分区备份就重写 GPT，刷完会没有信号。已中止，设备未被修改。"
	}
	fastboot get_staged "$p.bin" >/dev/null 2>&1 || die "[错误] 读取 $p 失败"
	[ -s "$p.bin" ] || die "[错误] 没有生成 $p.bin"
}

# ---------- 1. fastboot ----------
echo "[1/6] 切换到 fastboot 模式"
if adb get-state >/dev/null 2>&1; then
	say "      检测到 Android 设备，正在重启到 fastboot ..."
	adb reboot bootloader
else
	say "      没有检测到 adb 设备。"
	say "      如果屏幕已显示 FASTBOOT 可直接继续；否则请先打开 USB 调试。"
fi
wait_fastboot 90 || die "[错误] 90 秒内没有检测到 fastboot 设备。"
ok "      OK"; echo

# ---------- 2. lk2nd ----------
echo "[2/6] 刷入 lk2nd 临时引导并重启"
fastboot erase boot >/dev/null 2>&1 || true
fb flash boot lk2nd.img
fastboot reboot >/dev/null 2>&1
say "      等待设备重新进入 fastboot ..."
wait_fastboot 120 || die "[错误] lk2nd 启动后没有回到 fastboot。"
ok "      OK"; echo

# ---------- 3. 备份校准 ----------
echo "[3/6] 备份 modem 校准分区（很重要，别跳过）"
dump_part fsc
dump_part fsg
dump_part modemst1
dump_part modemst2
ok "      OK：fsc.bin / fsg.bin / modemst1.bin / modemst2.bin 已保存"
warn "      建议把这 4 个文件复制出来单独存一份。"
echo

# ---------- 4. GPT + bootloader ----------
echo "[4/6] 重写分区表并刷入 bootloader"
# 原厂 GPT 里没有 lk2nd 分区，这条会报错，属正常，忽略即可
fastboot erase lk2nd  >/dev/null 2>&1 || true
fastboot erase boot   >/dev/null 2>&1 || true
fastboot reboot bootloader >/dev/null 2>&1
wait_fastboot 90 || die "[错误] 重新进入 bootloader 失败。"
fb flash partition gpt_both0-fixed.bin
fb flash hyp   hyp.mbn
fb flash rpm   rpm.mbn
fb flash sbl1  sbl1.mbn
fb flash tz    tz.mbn
fb flash aboot aboot.bin
fb flash cdt   sbc_1.0_8016.bin
ok "      OK"; echo

# ---------- 5. 回填 ----------
echo "[5/6] 回填校准分区（必须在重写 GPT 之后）"
fb flash fsc      fsc.bin
fb flash fsg      fsg.bin
fb flash modemst1 modemst1.bin
fb flash modemst2 modemst2.bin
ok "      OK"; echo

# ---------- 6. 镜像 ----------
echo "[6/6] 刷入 OpenWrt 镜像"
fastboot erase boot        >/dev/null 2>&1 || true
fastboot erase rootfs      >/dev/null 2>&1 || true
fastboot erase rootfs_data >/dev/null 2>&1 || true
fastboot reboot bootloader >/dev/null 2>&1
wait_fastboot 90 || die "[错误] 重新进入 bootloader 失败。"
fb flash boot   boot.img
fb flash rootfs rootfs.img
ok "      OK"; echo

echo "全部完成，正在重启到 OpenWrt ..."
fastboot reboot >/dev/null 2>&1 || true
echo
echo "首次开机需要 1~3 分钟（自动格式化 rootfs_data、生成 SSH 密钥、拉起 modem）。"
echo "之后："
echo "  WiFi  SSID  ImmortalWrt   无密码"
echo "  管理  http://192.168.10.1  （默认无密码）"
echo "  USB   adb shell 可直接登录"
echo
echo "modem 起不来就等 3 分钟，日志：logread -e auto-apn"
