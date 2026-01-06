# ZYNQ_PCIE
XC7Z035+AD9268+AD9788，基于ZYNQ的光声图像采集与PCIE传输工程（所有值传输），包含verilog源代码、BlockDesign、Qt上位机代码。

该工程基于VIVADO 2018.3的Block Design设计，需要进行IP间的连接。实现光声成像数据采集、扫描波形输出、数据传输与接收功能。

PCIE传输基于RIFFA框架，RIFFA版本2.2.2，根据文件名称判断PCIE IP核速率和通道数（GEN1/GEN2 x4/x8）。（PCIE IP调用包含在adc2pcie.v）
