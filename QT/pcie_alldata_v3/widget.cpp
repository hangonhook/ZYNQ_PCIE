#include "widget.h"
#include "ui_widget.h"
#include <stdlib.h>
#include <stdio.h>
#include <windows.h>
#include "timer.h"
#include "riffa.h"
#include <QString>
#include <QTime>
#include <QPalette>
#include <QPixmap>
#include <QImage>
#include <QRgb>
#include <QFile>
#include <QDataStream>
#include <QFileDialog>
#include <QDebug>
#include <QMessageBox>
#include <malloc.h> // Windows 4KB对齐必需

Widget::Widget(QWidget *parent) :
    QWidget(parent),
    ui(new Ui::Widget),
    fpga(nullptr),
    sendBuffer(nullptr),
    recvBuffer(nullptr),
    currentRecvBuffer(nullptr),  // 初始化数据保存指针
    validDataPtr(nullptr),       // 初始化有效数据指针
    validDataSize(0)             // 初始化有效数据大小
{
    ui->setupUi(this);
    // 窗口设置
    this->setWindowTitle("PCIe图像助手_所有值");

    // FPGA设备检测
    fpga_info_list info; // FPGA设备信息结构体

    /* 设备检测状态处理 */
    if (fpga_list(&info) != 0) {                    // 驱动检测失败
        ui->comboBox->addItem("未检测到设备（驱动错误）");
    }
    else if(info.num_fpgas==0){                     // 无FPGA设备
        ui->comboBox->addItem("未检测到设备");
    }
    else{                                           // 检测到可用设备
        ui->comboBox->addItem("读取图像");
    }

    // UI元素初始化
    ui->startButton->setText("开始");    // 开始按钮
    ui->closeButton->setText("关闭");    // 关闭按钮
    ui->closeButton->setEnabled(false); // 初始时关闭按钮不可用
    ui->saveButton->setText("保存");     // 数据保存按钮
    ui->phaseButton->setText("相位+"); //相位增加按钮
    // 分辨率选择下拉框
    ui->pix->addItem("256X256");
    ui->pix->addItem("512X512");
    ui->pix->addItem("255X256");


}

/* 析构函数：资源回收 */
Widget::~Widget()
{
    closepcie();    // 关闭FPGA连接
    delete ui;      // 删除UI对象

}

/* 初始化FPGA连接和缓冲区 */
int Widget::openpcie()
{
    // 编译环境检查 (防止32位程序崩溃)
    if (sizeof(void*) != 8) {
        QMessageBox::critical(this, "严重错误", "请使用 64位 编译器构建此程序！\n32位程序无法处理 1024x1024 模式的大内存。");
        return 1;
    }

    // 解析分辨率
    QString res = ui->pix->currentText();
    if (res == "256X256") {
        image_h = 256; image_v = 256; samp_point = 512;
    } else if (res == "512X512") {
        image_h = 512; image_v = 512; samp_point = 512;
    } else { // 255X256
        image_h = 255; image_v = 256; samp_point = 512;
    }

    int i;
    if(ui->comboBox->currentIndex()==0){        // 确保在读取图像模式
        id = 0;                                 // FPGA设备ID
        chnl = 0;                               // 通信通道号
        // 计算总数据量 注意numWords位数和类型
        size_t totalPoints = (size_t)image_h * image_v * samp_point;
        numWords = totalPoints / 2;

        // 打开FPGA设备
        fpga = fpga_open(id);
        if (!fpga) {
            QMessageBox::critical(this, "错误", "FPGA连接失败");
            return 1;
        }

        /* 内存分配 */
        // 发送缓冲区（10个32位字）
        sendBuffer = (unsigned int *)malloc(10*4);  // 分配40字节（10个32位字）

        // 接收缓冲区
        //recvBuffer = (unsigned int *)malloc(numWords*4);   // 分配接收数据空间
        size_t bufferSize = numWords * 4;
        recvBuffer = (unsigned int *)__mingw_aligned_malloc(bufferSize + 4096 , 4096); // 4KB对齐 多分配4KB缓冲空间

        if (!sendBuffer || !recvBuffer) {
            QMessageBox::critical(this, "错误", "内存分配失败 (可能内存不足)");
            closepcie();
            return 1;
        }

        // 初始化测试数据 1~10
        for (i = 0; i < 10; i++) {
            sendBuffer[i] = i+1;
        }
    }

    // 初始化指针状态
    currentRecvBuffer = recvBuffer;
    validDataPtr = nullptr;
    validDataSize = 0;

    return 0;
}

/* 关闭FPGA连接并释放资源 */
void Widget::closepcie()
{
    if (fpga) fpga_close(fpga);
    if (sendBuffer) free(sendBuffer);
    // 释放对齐内存
    if (recvBuffer) __mingw_aligned_free(recvBuffer);
    fpga = nullptr;
    sendBuffer = nullptr;
    recvBuffer = nullptr;
    currentRecvBuffer = nullptr;
    validDataPtr = nullptr;
}

/* 开始按钮点击事件处理 */
void Widget::on_startButton_clicked()
{
    // 如果未连接，先初始化连接
    if (fpga == nullptr) {
        if (openpcie() != 0) return;
        ui->closeButton->setEnabled(true); // 启用关闭按钮
    }

    // 执行单次操作
    processSingleFrame();
}

/* 关闭按钮点击事件处理 */
void Widget::on_closeButton_clicked() {
    closepcie();
    ui->closeButton->setEnabled(false); // 禁用关闭按钮
    ui->startButton->setText("开始");
}

/* 相位+按钮点击事件处理 */
void Widget::on_phaseButton_clicked()
{
    // 如果未连接，先初始化连接
    if (fpga == nullptr) {
        if (openpcie() != 0) return;
    }

    // 防止命令冲突
    if (isCommandBusy) {
        QMessageBox::warning(this, "忙", "请等待上一命令完成");
        return;
    }
    isCommandBusy = true;

    unsigned int phaseCmd[1] = {20}; // 仅1个字（32'd20）
    // 发送1个32'd20的数据
    int sent = fpga_send(fpga, chnl, phaseCmd, 1, 0, 1, 5000);

    if (sent <= 0) {
        QMessageBox::warning(this, "警告", "相位触发发送失败");
    } else {
        // 尝试接收可能残留的脏数据。
        int recvd = fpga_recv(fpga, chnl, recvBuffer, numWords, 50);

        if (recvd > 0) {
            // 这种情况说明确实有脏数据，我们已经把它读出来扔掉了，保护了下一次采集
            qDebug() << "【安全清洗】检测并丢弃了相位操作产生的脏数据：" << recvd << "个字";
        } else {
            // recvd == 0，说明管道很干净，没有脏数据
            qDebug() << "【安全清洗】管道干净，无残留。";
        }

        //弹出成功提示
        QMessageBox::information(this, "成功", "相位触发发送成功");
    }

    isCommandBusy = false;

}

// 单次发送-接收-显示流程
void Widget::processSingleFrame() {
    // 1. 防止命令冲突
    if (isCommandBusy) {
        QMessageBox::warning(this, "忙", "请等待上一命令完成");
        return;
    }
    isCommandBusy = true;
    ui->startButton->setText("采集中...");

    // =========================================================
    // 【步骤 0】轻量级清洗 (Flush)
    // 虽然你的代码能跑，但加个清洗会更稳，防止上一帧的尾巴干扰
    // =========================================================
    unsigned int dummyBuf[1024];
    int flushed = 0;
    // 非阻塞读取 (Timeout=0)，有一点读一点，读完拉倒
    while (fpga_recv(fpga, chnl, dummyBuf, 1024, 0) > 0) {
        flushed++;
    }

    // =========================================================
    // 【步骤 1】发送开始命令 (32'd10)
    // =========================================================
    unsigned int startCmd[1] = {10};
    int sent = fpga_send(fpga, chnl, startCmd, 1, 0, 1, 5000);

    if (sent <= 0) {
        QMessageBox::warning(this, "通信失败", "发送开始命令(CMD 10)超时！\n请检查FPGA是否烧录或PCIe连接。");
        ui->startButton->setText("开始");
        isCommandBusy = false;
        return;
    }

    // =========================================================
    // 【步骤 2】接收数据
    // =========================================================
    // 你的逻辑：超时给够，空间给够
    if(sent > 0) {
        int recvd = fpga_recv(fpga, chnl, recvBuffer, numWords + 4096, 15000);

        if (recvd <= 0) {
            QMessageBox::warning(this, "接收失败", "未收到任何数据 (recvd <= 0)。\n请确认FPGA是否有数据发出。");
        }
        else {
            // =========================================================
            // 【核心逻辑】搜包头 + 详细诊断
            // =========================================================
            uint32_t* ptr32 = (uint32_t*)recvBuffer;
            int magicIndex = -1;

            // 搜索前 4096 个字
            int searchLimit = (recvd < 4096) ? recvd : 4096;
            for (int i = 0; i < searchLimit; i++) {
                if (ptr32[i] == 0xAAAA5555) {
                    magicIndex = i;
                    break;
                }
            }

            // --- 构造诊断信息 ---
            QString statusMsg;
            int dataStartIndex = -1;
            int actualPayloadWords = 0;
            int neededPayloadWords = numWords;

            if (magicIndex != -1) {
                // 找到了包头
                dataStartIndex = magicIndex + 1; // 包头后一位开始是数据
                actualPayloadWords = recvd - dataStartIndex;

                // 判断数据够不够
                bool isDataEnough = (actualPayloadWords >= neededPayloadWords - 128); // 允许少一点点(容错)

                statusMsg = QString(
                                "【%1】\n\n"
                                "1. 接收总量 (recvd): %2 字\n"
                                "2. 包头位置 (Index): %3\n"
                                "   (Frame ID: %4)\n"
                                "3. 有效负载 (Payload): %5 字\n"
                                "4. 期望负载 (Expected): %6 字\n"
                                "5. 差值 (Diff): %7 字"
                                )
                                .arg(isDataEnough ? "数据正常" : "数据不足")
                                .arg(recvd)
                                .arg(magicIndex)
                                .arg(magicIndex > 0 ? QString::number(ptr32[magicIndex-1]) : "无(Index=0)")
                                .arg(actualPayloadWords)
                                .arg(neededPayloadWords)
                                .arg(actualPayloadWords - neededPayloadWords);

                if (isDataEnough) {
                    // --- 成功 ---
                    // 只有在这里才更新图像
                    validDataPtr = (uint16_t*)(ptr32 + dataStartIndex);
                    validDataSize = (qint64)image_h * image_v * samp_point * sizeof(uint16_t);

                    processAndDisplayImage();

                    // 【调试弹窗】如果你觉得每次成功都弹窗太烦，可以把下面这行注释掉
                    // 但现在为了调试，我先留着
                    QMessageBox::information(this, "接收成功详情", statusMsg);
                }
                else {
                    // --- 失败：数据不够 ---
                    validDataPtr = nullptr;
                    QMessageBox::warning(this, "数据严重缺失", statusMsg + "\n\n建议：检查FPGA发送长度或FIFO是否溢出。");
                }
            }
            else {
                // --- 失败：没找到包头 ---
                QString hexDump;
                for(int k=0; k<10 && k<recvd; k++)
                    hexDump += QString("0x%1 ").arg(ptr32[k], 8, 16, QChar('0')).toUpper();

                statusMsg = QString(
                                "【同步失败：未找到包头 0xAAAA5555】\n\n"
                                "1. 接收总量: %1 字\n"
                                "2. 搜索范围: 前 %2 字\n"
                                "3. 前10个数据内容:\n%3"
                                )
                                .arg(recvd)
                                .arg(searchLimit)
                                .arg(hexDump);

                validDataPtr = nullptr;
                QMessageBox::critical(this, "同步错误", statusMsg);
            }
        }
    }

    ui->startButton->setText("下一张");
    isCommandBusy = false;
}

// 处理并显示图像
void Widget::processAndDisplayImage() {
    // 1. 检查数据有效性
    if (validDataPtr == nullptr) return;

    uint16_t *rawVolume = validDataPtr; // 使用跳过包头后的指针

    // 2. 准备 2D 投影图像的数据容器
    int pixelsPerFrame = image_v * image_h;

    // 使用 vector 临时存储投影后的 2D 数据
    std::vector<uint16_t> mipData(pixelsPerFrame);
    uint16_t globalMax = 0; // 记录整张图的最大值

    // ==========================================
    // MIP (最大值投影) 算法
    // ==========================================

    for (int i = 0; i < pixelsPerFrame; i++) {
        uint16_t localMax = 0;

        // 计算该像素点在 3D 数组中的起始偏移量
        size_t baseOffset = (size_t)i * samp_point;

        // 遍历深度点，找最大值
        for (int z = 0; z < samp_point; z++) {
            uint16_t val = rawVolume[baseOffset + z];
            if (val > localMax) localMax = val;
        }

        mipData[i] = localMax;

        // 更新全局最大值
        if (localMax > globalMax) globalMax = localMax;
    }

    // 3. 创建 QImage
    QImage image(image_v, image_h, QImage::Format_Grayscale8);

    // 4. 填充 QImage (归一化到 0-255)
    for (int y = 0; y < image_h; y++) {
        uchar* scanLine = image.scanLine(y);
        for (int x = 0; x < image_v; x++) {
            int idx = y * image_v + x;
            uint16_t val = mipData[idx];

            uchar gray = (globalMax == 0) ? 0 :
                             static_cast<uchar>((static_cast<uint32_t>(val) * 255) / globalMax);

            scanLine[x] = gray;
        }
    }

    // 5. 显示
    QPixmap pixmap = QPixmap::fromImage(image).scaled(
        ui->label->size(),
        Qt::KeepAspectRatio,
        Qt::SmoothTransformation
        );
    ui->label->setPixmap(pixmap);
    ui->label->setAlignment(Qt::AlignCenter);
}

/* 数据保存按钮点击事件处理 */
void Widget::on_saveButton_clicked() {
    // 检查当前缓冲区是否有效
    if (validDataPtr == nullptr) {
        QMessageBox::warning(this, "警告", "无有效数据可保存");
        return;
    }

    // 1. 获取保存路径
    QString defaultName = QString("image_%1x%2.dat").arg(image_v).arg(image_h);
    QString filename = QFileDialog::getSaveFileName(
        this,
        "保存16位原始数据",
        QDir::homePath() + "/" + defaultName,
        "DAT文件 (*.dat);;所有文件 (*)"
        );

    if (filename.isEmpty()) return;

    if (!filename.endsWith(".dat", Qt::CaseInsensitive)) {
        filename += ".dat";
    }

    // 2. 保存文件
    QFile file(filename);
    if (!file.open(QIODevice::WriteOnly)) {
        QMessageBox::critical(this, "错误",
                              QString("无法创建文件:\n%1\n错误: %2")
                                  .arg(filename)
                                  .arg(file.errorString()));
        return;
    }

    // 3. 写入纯净的16位样本数据（跳过了包头）
    // 使用 validDataPtr 和 validDataSize
    qint64 bytesWritten = file.write(reinterpret_cast<const char*>(validDataPtr), validDataSize);

    file.close();

    // 4. 验证写入结果
    if (bytesWritten != validDataSize) {
        QMessageBox::critical(this, "错误",
                              QString("写入不完整!\n期望: %1 字节\n实际: %2 字节")
                                  .arg(validDataSize)
                                  .arg(bytesWritten));
        return;
    }

    // 5. 成功反馈
    QMessageBox::information(this, "保存成功",
                             QString("16位原始数据已保存至:\n%1\n\n尺寸: %2x%3x%4\n文件大小: %5 MB")
                                 .arg(filename)
                                 .arg(image_v).arg(image_h).arg(samp_point)
                                 .arg(bytesWritten / (1024.0 * 1024.0), 0, 'f', 2));
}
