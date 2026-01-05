#ifndef WIDGET_H
#define WIDGET_H

#include <QWidget>
#include <QTimer>
#include "riffa.h"
#include <QFile>
#include <QDataStream>
#include <QFileDialog>
#include <QImage>

namespace Ui {
class Widget;
}

class Widget : public QWidget
{
    Q_OBJECT

public:
    explicit Widget(QWidget *parent = 0);
    ~Widget();

private slots:
    void on_startButton_clicked();  // 开始按钮
    void on_closeButton_clicked();  // 关闭按钮
    void on_saveButton_clicked();   // 保存按钮
    void on_phaseButton_clicked(); // 相位+按钮

private:
    Ui::Widget *ui;

    //FPGA相关
    fpga_t *fpga;
    fpga_info_list info;
    int id, chnl;
    unsigned int *sendBuffer;    // 发送缓冲区（10个32位测试数据）
    uint32_t *recvBuffer;        // 接收缓冲区
    uint32_t *currentRecvBuffer; // 当前显示数据指针
    uint16_t* validDataPtr;     // 【新增】用于指向去除包头后的有效数据
    qint64    validDataSize;    // 【新增】有效数据的总字节数

    // 图像参数
    int image_h, image_v, samp_point;        // 分辨率（高度、宽度），采样点数
    size_t numWords;               // 总数据 = image_h * image_v * samp_point

    bool isCommandBusy = false; // 标记命令是否进行中

    // 功能函数
    int openpcie();              // 初始化FPGA连接
    void closepcie();            // 关闭FPGA连接
    void processAndDisplayImage(); // 处理并显示图像
    void processSingleFrame();   // 单次发送-接收-显示流程
};

#endif // WIDGET_H
