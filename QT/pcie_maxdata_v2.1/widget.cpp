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
    currentRecvBuffer(nullptr)  // 初始化数据保存指针
{
    ui->setupUi(this);
    // 窗口设置
    this->setWindowTitle("PCIe图像助手_最大值");

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
    ui->pix->addItem("1024X1024");


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
    // 解析分辨率
    QString res = ui->pix->currentText();
    if (res == "256X256") {
        image_h = 256; image_v = 256;
    } else if (res == "512X512") {
        image_h = 512; image_v = 512;
    } else { // 1024X1024
        image_h = 1024; image_v = 1024;
    }

    int i;
    if(ui->comboBox->currentIndex()==0){        // 确保在读取图像模式
        id = 0;                                 // FPGA设备ID
        chnl = 0;                               // 通信通道号
        numWords = (image_h*image_v + 1) / 2;             // 计算总数据量 注意numWords位数和类型

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
        recvBuffer = (unsigned int *)_aligned_malloc((numWords * 2) * 4 , 4096); // 4KB对齐 多分配4KB缓冲空间

        if (!sendBuffer || !recvBuffer) {
            QMessageBox::critical(this, "错误", "内存分配失败");
            closepcie();
            return 1;
        }

        // 初始化测试数据 1~10
        for (i = 0; i < 10; i++) {
            sendBuffer[i] = i+1;
        }
    }
    currentRecvBuffer = recvBuffer;
    return 0;
}

/* 关闭FPGA连接并释放资源 */
void Widget::closepcie()
{
    if (fpga) fpga_close(fpga);
    if (sendBuffer) free(sendBuffer);
    //if (recvBuffer) free(recvBuffer);
    if (recvBuffer) _aligned_free(recvBuffer);
    fpga = nullptr;
    sendBuffer = nullptr;
    recvBuffer = nullptr;
    currentRecvBuffer = nullptr;
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
        // 参数说明：
        // buffer: 直接复用 recvBuffer（它足够大，存垃圾数据没问题）
        // len:    numWords（尝试读一整帧的最大量，能读多少读多少）
        // timeout: 50 (关键！只等待50毫秒。如果没有数据，50ms后自动继续，不会卡死)
        int recvd = fpga_recv(fpga, chnl, recvBuffer, numWords, 50);

        if (recvd > 0) {
            // 这种情况说明确实有脏数据，我们已经把它读出来扔掉了，保护了下一次采集
            qDebug() << "【安全清洗】检测并丢弃了相位操作产生的脏数据：" << recvd << "个字";
        } else {
            // recvd == 0，说明管道很干净，没有脏数据，这是好事
            qDebug() << "【安全清洗】管道干净，无残留。";
        }

        //弹出成功提示
        QMessageBox::information(this, "成功", "相位触发发送成功");
    }

    isCommandBusy = false;

}

// 单次发送-接收-显示流程
void Widget::processSingleFrame() {

    // 防止命令冲突
    if (isCommandBusy) {
        QMessageBox::warning(this, "忙", "请等待上一命令完成");
        return;
    }
    isCommandBusy = true;

    unsigned int startCmd[1] = {10}; // 仅1个字（32'd10）

    // 发送1个32'd10的数据
    int sent = fpga_send(fpga, chnl, startCmd, 1, 0, 1, 5000);
    if (sent <= 0) {
        QMessageBox::warning(this, "警告", "开始触发发送失败");
        isCommandBusy = false;
        return;
    }

    // 接收数据
    if(sent > 0) {
        int recvd = fpga_recv(fpga, chnl, recvBuffer, numWords, 25000);
        if (recvd <= 0) {
            QMessageBox::warning(this, "警告", "数据接收失败");
            isCommandBusy = false;
            return;
        }// 接收成功更新显示
        else
            processAndDisplayImage();
    }

    // 等待下一次操作
    ui->startButton->setText("下一张");

    isCommandBusy = false;
}

// 处理并显示图像
void Widget::processAndDisplayImage() {
    // 1. 计算16位样本最大值
    uint16_t *samples = reinterpret_cast<uint16_t*>(recvBuffer); // 关键：直接视为16位数组
    int totalSamples = image_v * image_h;

    // 2. 计算最大值（在16位数据上）
    uint16_t maxValue = 0;
    for (int i = 0; i < totalSamples; i++) {
        if (samples[i] > maxValue) maxValue = samples[i];
    }

    // 3. 创建正确尺寸的图像
    QImage image(image_v, image_h, QImage::Format_Grayscale8);

    // 4. 填充像素 (按行优先)
    for (int y = 0; y < image_h; y++) {
        for (int x = 0; x < image_v; x++) {
            int idx = y * image_v + x; // 行优先索引
            if (idx < totalSamples) {
                uchar gray = (maxValue == 0) ? 0 :
                                 static_cast<uchar>((static_cast<uint32_t>(samples[idx]) * 255) / maxValue);
                image.setPixel(x, y, gray);
            }
        }
    }

    // 5. 显示（保持比例）
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
    if (currentRecvBuffer == nullptr) {
        QMessageBox::warning(this, "警告", "无有效数据可保存");
        return;
    }

    // 1. 获取保存路径（默认文件名包含尺寸）
    QString defaultName = QString("image_%1x%2.dat").arg(image_v).arg(image_h);
    QString filename = QFileDialog::getSaveFileName(
        this,
        "保存16位原始数据",
        QDir::homePath() + "/" + defaultName,
        "DAT文件 (*.dat);;所有文件 (*)"
        );

    if (filename.isEmpty()) return;

    // 2. 确保文件后缀为.dat
    if (!filename.endsWith(".dat", Qt::CaseInsensitive)) {
        filename += ".dat";
    }

    // 3. 保存16位原始数据
    QFile file(filename);
    if (!file.open(QIODevice::WriteOnly)) {
        QMessageBox::critical(this, "错误",
                              QString("无法创建文件:\n%1\n错误: %2")
                                  .arg(filename)
                                  .arg(file.errorString()));
        return;
    }

    // 4. 写入16位样本数据（关键：不是32位字！）
    uint16_t *samples = reinterpret_cast<uint16_t*>(currentRecvBuffer);
    int totalSamples = image_v * image_h;
    qint64 expectedBytes = totalSamples * sizeof(uint16_t);
    qint64 bytesWritten = file.write(reinterpret_cast<const char*>(samples), expectedBytes);
    file.close();
    // 5. 验证写入结果
    if (bytesWritten != expectedBytes) {
        QMessageBox::critical(this, "错误",
                              QString("写入不完整!\n期望: %1 字节\n实际: %2 字节")
                                  .arg(expectedBytes)
                                  .arg(bytesWritten));
        return;
    }

    // 6. 成功反馈
    QMessageBox::information(this, "保存成功",
                             QString("16位原始数据已保存至:\n%1\n\n尺寸: %2×%3 像素\n数据量: %4 KB")
                                 .arg(filename)
                                 .arg(image_v)
                                 .arg(image_h)
                                 .arg(expectedBytes / 1024.0, 0, 'f', 1));
}
