# OpenWifi v1.5.0 Porting to RK-ZYNQ7020-F + AD-FMCOMMS3-EBZ

本仓库提供了将开源全栈 Wi-Fi 芯片组 **OpenWifi (v1.5.0)** 成功移植到目前国内高性价比的 **RK-ZYNQ7020-F**（1GB DDR3 自定义开发板）搭配 **AD-FMCOMMS3-EBZ**（AD9361）射频子板上的完整软硬件适配与系统级标定方案。

## 1. 硬件平台与原理图参数

*   **SoC**: Xilinx Zynq-7000 XC7Z020-2CLG484I
*   **Carrier Board**: RK-ZYNQ7020-F (米联客/自制 1GB 内存版)
    *   **内存**: 1GB DDR3 (MT41J256M16)
    *   **调试串口**: UART0 (映射在 MIO 10-11 管脚)
    *   **以太网 PHY**: Realtek RTL8211F 千兆以太网芯片 ( gem0, PHY ADDR=1 )
    *   **无外设**: 无 HDMI、无音频 Codec (ADAU1761) 芯片
*   **RF Board**: AD-FMCOMMS3-EBZ (基于原装/高精度 Rakon E2809 TCXO 40MHz 时钟源)

---

## 2. 核心技术攻关要点 (Key Engineering Breakthroughs)

本适配方案在移植过程中解决了以下四个导致系统死锁、不工作或无响应的底层硬伤：

### 2.1 软硬协同 1GB 内存防 DMA 越界死锁 (dma-ranges)
在 Zynq-7000 架构中，接收 DMA (`axi_dma_1`) 通过 **`S_AXI_ACP`** 端口连接。若直接在 Vivado 中将 DMA 寻址范围扩大到 1G：
*   容易导致 FPGA 接收端时序违规（Timing FAILED）。
*   当 Linux 的连续内存分配器（CMA）将网卡缓冲区分配到 512MB 以上的高端内存时，ACP 端口会发生总线死锁，导致加载驱动时产生致命的 `Internal error: Oops: 5 (cma_allocator_free)` 崩溃。

**解决方案（软硬协同方案）**：
1.  在 Vivado Address Editor 中，保持所有的 DMA 寻址范围在标准的 **`512M`**（保障布线极易闭合，防止总线死锁）。
2.  在设备树（DTS）中宣告系统拥有 **1G 物理内存**，但在 `fpga-axi@0` 节点下，注入 **`dma-ranges`** 物理限制属性：
    ```dts
    fpga-axi@0 {
        compatible = "simple-bus";
        #address-cells = <0x1>;
        #size-cells = <0x1>;
        ranges;
        /* 强行警告内核：FPGA 的 DMA 只被允许分配在 DDR 的前 512MB 物理空间中 */
        dma-ranges = <0x00000000 0x00000000 0x20000000>;
    };
    ```
3.  在 `uEnv.txt` 中配置 **`mem=1G`**，此时 CPU 与用户空间软件可以自由享受 1GB RAM，而无线网卡的数据通道获得了 100% 的内存安全保障。

### 2.2 接收采样时钟未激活故障 (fpga_clk Fix)
在 5.15 内核中，由于设备树中的 ADC 节点（`cf-ad9361-lpc`）漏配了时钟名称，导致内核的 Common Clock 框架在开机时认为没有外设需要接收采样时钟，从而在物理上将其关闭（使能计数为 0），解调器由于没有时钟而彻底失聪。

**解决方案**：
在 `cf-ad9361-lpc@79020000` 节点下，补齐时钟名绑定，将其映射为 **`"fpga_clk"`**：
```dts
cf-ad9361-lpc@79020000 {
    compatible = "adi,axi-ad9361-6.00.a";
    reg = <0x79020000 0x6000>;
    clocks = <0x11 0xc>;       /* 时钟 ID 12 代表 rx_sampl_clk */
    clock-names = "fpga_clk";  /* 驱动必须以此名字激活接收时钟 */
    spibus-connected = <0x11>;
};

2.3 裁剪 HDMI 导致的管脚编译报错

移除 HDMI 和音频相关的物理 IP 后，必须在 system.xdc 约束文件中完全注释掉相关的引脚约束。否则 Vivado 会因为物理 Port 缺失而在 Placer 阶段抛出 Place 30-58 / Place 30-99 致命错误。
2.4 +50kHz 载波频偏物理补偿 (CFO Calibration)

受限于定制板卡与商业手机晶振在高温下的相对物理温漂，手机发出的 Wi-Fi 数据包对容忍度极低的 FPGA 接收解调器来说存在频偏。
在 2.4GHz（信道 1）下，通过物理标定：本系统存在 +50kHz (约 20.7 PPM) 的相对偏差。在启动后必须手动在软件层进行微调补偿，即可实现手机的秒连。
3. 快速启动与通车指南
3.1 烧录 SD 卡准备

    BOOT 分区 (FAT32)：将打包好的 BOOT.BIN、uImage、编译好的 devicetree.dtb 拷入。

    uEnv.txt 写入：
    code Text

    bootargs=console=ttyPS0,115200 root=/dev/mmcblk0p2 rw rootwait clk_ignore_unused mem=1G
    uenvcmd=fatload mmc 0 0x3000000 uImage && fatload mmc 0 0x2A00000 devicetree.dtb && bootm 0x3000000 - 0x2A00000

    天线连接物理规范：
    由于驱动默认使用了 TX2A 和 RX1A 跨通道以保证最高电磁隔离度。天线必须拧在：

        TX2A（通道 1，发射端）

        RX1A（通道 0，接收端）

3.2 系统内一键通车脚本 (sdr_calibration_startup.sh)

将本项目 boot_pack/sdr_calibration_startup.sh 拷贝至开发板 /root/openwifi/ 下，运行即可完成一键驱动挂载、发射功率对齐、频偏补偿与 DHCP 发牌服务拉起：
code Bash

#!/bin/bash
cd /root/openwifi

# 1. 加载驱动
sudo ./wgd.sh

# 2. 启动 2.4G 开放热点
sudo ./fosdem-11ag.sh

# 3. 强行固定接收天线为 60dB 监听增益
sudo ./set_rx_gain_manual.sh 60

# 4. 微调物理接收频率，向上偏移 50kHz 对齐手机温漂频偏
sudo sh -c "echo 2412050000 > /sys/bus/iio/devices/iio:device1/out_altvoltage0_RX_LO_frequency"

# 5. 微调两路发射天线衰减为 15dB，建立“不聋不哑”的黄金无线平衡
sudo sh -c "echo -15 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain"
sudo sh -c "echo -15 > /sys/bus/iio/devices/iio:device1/out_voltage1_hardwaregain"

# 6. 配置网卡 IP
sudo ifconfig sdr0 192.168.13.1 netmask 255.255.255.0 up

# 7. 强杀残留进程，启动前台 DHCP 服务
sudo killall dhcpd
sudo rm -f /var/run/dhcpd.pid
sudo dhcpd -f -d -cf /etc/dhcp/dhcpd.conf sdr0

