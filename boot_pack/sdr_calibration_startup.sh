#!/bin/bash
cd /root/openwifi

# 1. 强杀可能冲突的旧服务进程
sudo killall hostapd 2>/dev/null
sudo killall dhcpd 2>/dev/null
sudo rm -f /var/run/dhcpd.pid

# 2. 物理重置网卡模式
sudo ifconfig sdr0 down
sudo iw dev sdr0 set type __ap
sudo ifconfig sdr0 up

# 3. 启动 2.4G 开放热点（后台运行）
sudo ./fosdem-11ag.sh

# 4. 强制网卡绑定网关 IP，并将接收增益固定在 60dB 敏锐状态
sudo ifconfig sdr0 192.168.13.1 netmask 255.255.255.0 up
sudo /root/openwifi/set_rx_gain_manual.sh 60

# 5. 【核心校准】：物理微调本振频率，向上偏移 50kHz 对齐晶振温漂
sudo sh -c "echo 2412050000 > /sys/bus/iio/devices/iio:device1/out_altvoltage0_RX_LO_frequency"

# 6. 【核心校准】：物理微调两路发射衰减至 15dB，建立黄金无线收发平衡
sudo sh -c "echo -15 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain"
sudo sh -c "echo -15 > /sys/bus/iio/devices/iio:device1/out_voltage1_hardwaregain"

# 7. 前台启动 DHCP 监听服务，静待手机加入！
sudo dhcpd -f -d -cf /etc/dhcp/dhcpd.conf sdr0
