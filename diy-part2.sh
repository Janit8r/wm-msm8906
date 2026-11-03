#!/bin/bash
#

# Modify default IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# eth0
sed -i "s/ucidef_set_interface_lan 'eth0'/ucidef_set_interface_lan 'br-lan'/" package/base-files/files/etc/board.d/99-default_network

# Modify default theme
sed -i 's/luci-theme-material/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# DbusSmsForwardCPlus
git clone https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus

# 北大源
cp -r "$GITHUB_WORKSPACE/scripts/files-8916" "$GITHUB_WORKSPACE/openwrt/files"
ls -R "$GITHUB_WORKSPACE/openwrt/files"

# 保证可执行位（git 在 Windows 上容易把 100755 丢成 100644，procd 会因此无法 exec）
chmod +x "$GITHUB_WORKSPACE/openwrt/files/etc/init.d/"* 2>/dev/null
chmod +x "$GITHUB_WORKSPACE/openwrt/files/usr/bin/"* 2>/dev/null
ls -l "$GITHUB_WORKSPACE/openwrt/files/etc/init.d/" "$GITHUB_WORKSPACE/openwrt/files/usr/bin/" 2>/dev/null


# 压制 GCC 14 类型错误
pwd
ls package/libs/libnftnl/Makefile
sed -i '/^TARGET_CFLAGS += \$(FPIC)/a TARGET_CFLAGS += -Wno-error=incompatible-pointer-types' package/libs/libnftnl/Makefile

# 验证
grep -n "Wno-error=incompatible-pointer-types" package/libs/libnftnl/Makefile && echo "✓ 修复已应用" || echo "✗ 修复失败"

[ -f include/toplevel.mk ] || cd "$GITHUB_WORKSPACE/openwrt" || exit 1
patch -p1 --fuzz=2 <<'EOF'
--- a/include/image.mk
+++ b/include/image.mk
@@ -192,7 +192,6 @@
   -Wno-unit_address_vs_reg \
   -Wno-avoid_unnecessary_addr_size \
   -Wno-alias_paths \
-  -Wno-graph_child_address \
   -Wno-simple_bus_reg
 
 DTC_FLAGS += $(DTC_WARN_FLAGS)
EOF
grep -q 'graph_child_address' include/image.mk && echo "FAIL: image.mk 未修复" || echo "OK: image.mk DTC 参数已修复"


FW4_SRC=$GITHUB_WORKSPACE/scripts/msm89xx/package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
FW4_PATCH=package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
FW4_VER=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' package/network/config/firewall4/Makefile)
echo "firewall4 pin: ${FW4_VER:-unknown}"

if [ "$FW4_VER" = "bac1d656e09b48e542f860844fe91cbba82abae2" ]; then
	if cp -f "$FW4_SRC" "$FW4_PATCH"; then
		echo "firewall4: local fullcone patch applied"
	else
		echo "::error::firewall4: local patch missing at $FW4_SRC"
	fi
else
	rm -f "$FW4_PATCH"
	git checkout -- package/network/config/firewall4
	echo "firewall4: pin changed, upstream patch restored"
fi

if grep -q "zone.dflags.helper = false;" "$FW4_PATCH" 2>/dev/null; then
	echo "firewall4 patch verify: OK"
else
	echo "::warning::firewall4 patch verify: failed"
fi



# ---- SimAdmin 预编译二进制（UPX 压缩）+ 前端 ----
# 二进制不随仓库提交（8MB+），构建时从 luci-app-simadmin 的滚动 Release 拉取。
bash "$GITHUB_WORKSPACE/scripts/install-simadmin-prebuilt.sh" "$GITHUB_WORKSPACE/openwrt/files"

# 没有二进制就别继续了——否则会静默产出一个没有 simadmin 的固件
if [ ! -x "$GITHUB_WORKSPACE/openwrt/files/opt/simadmin/simadmin" ]; then
	echo "::error::SimAdmin 预编译二进制缺失，固件将不含 simadmin，终止构建"
	exit 1
fi

# files/ 覆盖层里的脚本必须带可执行位，否则 procd 拉不起来
chmod +x "$GITHUB_WORKSPACE/openwrt/files/opt/simadmin/start.sh" 2>/dev/null
chmod +x "$GITHUB_WORKSPACE/openwrt/files/etc/init.d/"* 2>/dev/null
chmod +x "$GITHUB_WORKSPACE/openwrt/files/usr/bin/"* 2>/dev/null
chmod +x "$GITHUB_WORKSPACE/openwrt/files/usr/libexec/simadmin/"* 2>/dev/null
ls -l "$GITHUB_WORKSPACE/openwrt/files/opt/simadmin/"
