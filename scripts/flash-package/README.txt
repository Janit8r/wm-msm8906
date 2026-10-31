================================================================
 WF2 / UFI-W-001 (QRZL903, msm8916)  OpenWrt 刷机包
================================================================

这个包用于把「Android 原厂系统」的 WF2 随身 WiFi 刷成 OpenWrt。
里面已经包含了刷机需要的全部文件，不需要再下载别的东西。

注意：包里的 boot.img / rootfs.img 是配套的，不要和别的版本的
      刷机包混用，否则可能起不来。


----------------------------------------------------------------
一、包里有什么
----------------------------------------------------------------

  boot.img                内核 + 设备树（Android boot 格式）
  rootfs.img              OpenWrt 根文件系统（squashfs）
  lk2nd.img               临时引导，用来执行校准分区备份
  gpt_both0-fixed.bin     分区表（原厂布局和 OpenWrt 完全不同，必须重写）
                          这份是按 7,634,944 扇区（3.64GiB eMMC）做的，
                          和原厂 GPT 的几何完全一致，rootfs_data 能占满整片。
  aboot.bin / sbl1.mbn / tz.mbn / hyp.mbn / rpm.mbn / sbc_1.0_8016.bin
                          bootloader 各段
  adb.exe / fastboot.exe / AdbWinApi.dll / AdbWinUsbApi.dll
                          Windows 用的工具
  flash-windows.bat       Windows 一键刷机
  flash-linux.sh          Linux / macOS 一键刷机
  backup-edl.bat          EDL 模式下只读备份 modem 校准（可选，安全）
  emmcdl.exe / prog_emmc_firehose_8916.mbn
                          EDL 工具（只有 backup-edl.bat 用得到）
  version.txt             这一版固件的编译信息
  sha256sums.txt          镜像校验值


----------------------------------------------------------------
二、刷之前
----------------------------------------------------------------

1. 设备是 Android 原厂系统，能正常开机。
2. 打开「开发者选项 -> USB 调试」，电脑能 adb 认到设备。
   验证：adb devices 能看到设备号。
3. Windows 需要装好 USB 驱动（一般插上能 adb 就行）。
4. 解压整个压缩包到一个纯英文路径的目录（不要放在中文路径或
   C:\Program Files 下），然后在该目录里运行脚本。

**重要**：刷机会清空原厂 Android 和所有数据，不可恢复。
          如果设备里有重要东西，先拷出来。


----------------------------------------------------------------
三、刷一台设备
----------------------------------------------------------------

【Windows】
  1) 双击 flash-windows.bat
  2) 输入 Y 确认
  3) 脚本会自己把设备切到 fastboot，然后依次：
       刷 lk2nd -> 备份校准分区 -> 重写 GPT -> 刷 bootloader
       -> 回填校准分区 -> 刷 boot.img / rootfs.img
  4) 中间会停顿几秒等设备重新进 fastboot，属正常现象，别拔线
  5) 看到「全部完成」就拔掉，设备会自动重启进 OpenWrt

【Linux / macOS】
  chmod +x flash-linux.sh
  ./flash-linux.sh
  需要系统里已经有 adb / fastboot：
    Ubuntu/Debian:  sudo apt install android-sdk-platform-tools-common adb fastboot
    macOS:          brew install android-platform-tools

脚本会在当前目录生成 4 个校准备份文件：
  fsc.bin  fsg.bin  modemst1.bin  modemst2.bin
**把这 4 个文件复制出来单独存一份**，这是每台设备各自的 modem
校准数据，刷坏了只有它能救回来。不同设备的这 4 个文件不能混用。


----------------------------------------------------------------
四、批量刷多台
----------------------------------------------------------------

一台一台来，每台都完整跑一遍脚本。刷完一台后：
  1) 拔掉这台，插下一台
  2) 重新双击脚本（脚本每次都会重新检测设备）
  3) 重复

因为每台设备都有自己的校准分区，脚本必须每台都执行一次备份 +
回填，不能只刷镜像了事。想省时间也不要跳过第 3 步。

如果嫌手动点太慢，可以把每台的 4 个备份文件按设备号存到不同目录，
但回填这一步仍然要一台一台做。


----------------------------------------------------------------
五、刷完怎么验证
----------------------------------------------------------------

首次开机会自动做这些事，需要 1~3 分钟：
  - 格式化 rootfs_data（第一次会比较慢）
  - 生成 SSH 主机密钥
  - 等 modem 出现并启用、按 IMSI 自动配置 APN
  - 拉起 WiFi

验证：
  WiFi   搜 ImmortalWrt，无密码，连上后访问 http://192.168.10.1
  网口   电脑设 192.168.10.x，网关 192.168.10.1
  USB    adb shell 直接进（root，无密码）

设备上检查：
  mmcli -L                              # 应该能看到 modem
  mmcli -m 0 | grep -E 'state|operator' # 应该是 registered / connected
  ip -4 addr show wwan0                 # 应该有 IPv4
  ip route | grep default               # 应该有默认路由
  logread -e auto-apn                   # 看联网看护日志

注意：mmcli 里的 modem 编号不一定是 0，用 mmcli -L 看实际编号。
      simadmin 的网页接口在 http://127.0.0.1:3000（设备本机）。


----------------------------------------------------------------
六、出问题了
----------------------------------------------------------------

【fastboot 里提示 not allowed / 无法 flash】
  bootloader 没解锁。这类 msm8916 随身 WiFi 一般可以用
  fastboot oem unlock 解锁（会清数据），或者用 EDL 方案。

【设备进不去 fastboot】
  先试 adb reboot bootloader；
  还不行就 adb reboot edl 进 9008，用 QFIL 或 emmcdl 刷。

【脚本在「备份校准分区」这步停了】
  说明设备的 fastboot 不支持 oem dump。
  这时**不要**继续往下刷，否则 GPT 重写后校准分区会丢，刷完没信号。
  设备还停在 lk2nd 的 fastboot 里，原厂系统没被改，断电重启就能回去。

【刷完没有信号 / 没有 IMEI】
  说明校准分区没回填成功。重新跑一遍脚本（备份文件还在目录里，
  脚本会重新备份覆盖，如果设备已经是 OpenWrt 布局了，
  那就只能用之前单独存的那份校准文件手工写回）。

【刷完起不来，USB 也不枚举】
  接电脑看是不是进了 9008，用 QFIL 重刷。

【在「重写分区表」这步报 partition table 相关错误】
  说明这台设备的 eMMC 容量比 3.64GiB 小，和本包的 GPT 几何不匹配。
  这种情况**不要**继续往下刷，直接用 EDL 恢复原厂。
  正常 WF2 都是同一片 eMMC，不会遇到这个问题。

【刷完有 IP 但上不了网】
  等 2 分钟，看护脚本会自动重拨。
  还不行：logread -e auto-apn 看日志，
  检查 APN 是否正确（uci show network.modem）。


----------------------------------------------------------------
七、想刷回原厂
----------------------------------------------------------------

需要原厂固件的完整备份（本包不提供）。
大致流程：进 9008 -> QFIL 刷原厂包 -> 恢复本包 backup-edl 备份的
gpt_stock.bin 和 4 个校准分区。所以刷之前先把校准分区备份好。
