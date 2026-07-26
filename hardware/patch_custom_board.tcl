# =============================================================================
# === 针对您的自定义开发板的修改 (512M内存、删除HDMI/Audio、重映射UART0) ===
# =============================================================================

# A. 修改 DDR3 型号为 512MB (MT41J256M16) 并解决赛灵思负延迟时序报错
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
] [get_bd_cells sys_ps7]

# B. 强制删除 HDMI 相关的 IP 核及外部端口
catch {delete_bd_objs [get_bd_cells axi_hdmi_core]}
catch {delete_bd_objs [get_bd_cells axi_hdmi_clkgen]}
catch {delete_bd_objs [get_bd_cells axi_hdmi_dma]}
catch {delete_bd_ports hdmi_out_clk}
catch {delete_bd_ports hdmi_data}
catch {delete_bd_ports hdmi_data_e}
catch {delete_bd_ports hdmi_hsync}
catch {delete_bd_ports hdmi_vsync}

# C. 强制删除 Audio(I2S) 和 SPDIF 相关的 IP 核及外部端口
catch {delete_bd_objs [get_bd_cells axi_i2s_adi]}
catch {delete_bd_objs [get_bd_cells sys_audio_clkgen]}
catch {delete_bd_objs [get_bd_cells axi_spdif_tx_core]}
catch {delete_bd_ports i2s_mclk}
catch {delete_bd_ports i2s_bclk}
catch {delete_bd_ports i2s_lrclk}
catch {delete_bd_ports i2s_sdata_out}
catch {delete_bd_ports i2s_sdata_in}
catch {delete_bd_ports spdif}

# D. 彻底关闭和删除悬空的 HP0 总线
catch {delete_bd_objs [get_bd_cells axi_hp0_interconnect]}
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {0}] [get_bd_cells sys_ps7]

# E. 重映射 PS 侧引脚（禁用 UART1，开启您的串口 UART0、SD卡、eMMC 和 I2C，并彻底关闭冲突的写保护 WP 引脚）
set_property -dict [list \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE {0} \
  CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART0_UART0_IO {MIO 10 .. 11} \
  \
  CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
  CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
  CONFIG.PCW_SD0_GRP_CD_IO {MIO 9} \
  CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
  \
  CONFIG.PCW_SD1_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_SD1_SD1_IO {MIO 46 .. 51} \
  CONFIG.PCW_SD1_GRP_WP_ENABLE {0} \
  \
  CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_I2C0_I2C0_IO {MIO 14 .. 15} \
] [get_bd_cells sys_ps7]

# 保存修改后的原理图并进行验证
save_bd_design
validate_bd_design
