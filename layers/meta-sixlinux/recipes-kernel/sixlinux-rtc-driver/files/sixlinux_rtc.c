// SPDX-License-Identifier: GPL-2.0-only
/*
 * SixLinux PL031 RTC platform driver for MMIO/IRQ experiments.
 */

#include <linux/debugfs.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/rtc.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>

#define RTC_DR          0x00
#define RTC_MR          0x04
#define RTC_LR          0x08
#define RTC_CR          0x0c
#define RTC_IMSC        0x10
#define RTC_MIS         0x18
#define RTC_ICR         0x1c

#define RTC_CR_EN       BIT(0)
#define RTC_BIT_AI      BIT(0)

#define RTC_PID0        0xfe0
#define RTC_PID1        0xfe4
#define RTC_PID2        0xfe8
#define RTC_PID3        0xfec

struct sixlinux_rtc {
    void __iomem *base;
    int irq;
    u32 id;
    u32 data;
    u32 irq_count;
    spinlock_t lock;
    struct dentry *debugfs_dir;
    struct rtc_device *rtc_dev;
};

static void sixlinux_rtc_arm_alarm(struct sixlinux_rtc *rtc)
{
    unsigned long flags;

    spin_lock_irqsave(&rtc->lock, flags);
    writel(RTC_BIT_AI, rtc->base + RTC_ICR);
    writel(readl(rtc->base + RTC_DR) + 1, rtc->base + RTC_MR);
    writel(RTC_BIT_AI, rtc->base + RTC_IMSC);
    spin_unlock_irqrestore(&rtc->lock, flags);
}

static int sixlinux_rtc_read_time(struct device *dev, struct rtc_time *tm)
{
    struct sixlinux_rtc *rtc = dev_get_drvdata(dev);
    u32 seconds = readl(rtc->base + RTC_DR);

    rtc_time64_to_tm(seconds, tm);
    return 0;
}

static int sixlinux_rtc_set_time(struct device *dev, struct rtc_time *tm)
{
    struct sixlinux_rtc *rtc = dev_get_drvdata(dev);
    unsigned long flags;
    u32 seconds = (u32)rtc_tm_to_time64(tm);

    spin_lock_irqsave(&rtc->lock, flags);
    writel(seconds, rtc->base + RTC_LR);
    spin_unlock_irqrestore(&rtc->lock, flags);

    return 0;
}

static const struct rtc_class_ops sixlinux_rtc_ops = {
    .read_time = sixlinux_rtc_read_time,
    .set_time = sixlinux_rtc_set_time,
};

static irqreturn_t sixlinux_rtc_irq(int irq, void *dev_id)
{
    struct sixlinux_rtc *rtc = dev_id;
    unsigned long flags;
    u32 mis;

    spin_lock_irqsave(&rtc->lock, flags);
    mis = readl(rtc->base + RTC_MIS);
    if (!(mis & RTC_BIT_AI)) {
        spin_unlock_irqrestore(&rtc->lock, flags);
        return IRQ_NONE;
    }

    writel(RTC_BIT_AI, rtc->base + RTC_ICR);
    writel(0, rtc->base + RTC_IMSC);
    rtc->data = readl(rtc->base + RTC_DR);
    rtc->irq_count++;
    spin_unlock_irqrestore(&rtc->lock, flags);

    return IRQ_HANDLED;
}

static ssize_t sixlinux_rtc_trigger_write(struct file *file,
                                          const char __user *buf,
                                          size_t count, loff_t *ppos)
{
    struct sixlinux_rtc *rtc = file->private_data;
    u32 value;
    int ret;

    ret = kstrtou32_from_user(buf, count, 0, &value);
    if (ret)
        return ret;

    if (value)
        sixlinux_rtc_arm_alarm(rtc);

    return count;
}

static const struct file_operations sixlinux_rtc_trigger_fops = {
    .owner = THIS_MODULE,
    .open = simple_open,
    .write = sixlinux_rtc_trigger_write,
};

static int sixlinux_rtc_probe(struct platform_device *pdev)
{
    struct sixlinux_rtc *rtc;
    int ret;

    rtc = devm_kzalloc(&pdev->dev, sizeof(*rtc), GFP_KERNEL);
    if (!rtc)
        return -ENOMEM;

    rtc->base = devm_platform_ioremap_resource(pdev, 0);
    if (IS_ERR(rtc->base))
        return PTR_ERR(rtc->base);

    rtc->irq = platform_get_irq(pdev, 0);
    if (rtc->irq < 0)
        return rtc->irq;

    spin_lock_init(&rtc->lock);
    platform_set_drvdata(pdev, rtc);

    ret = devm_request_irq(&pdev->dev, rtc->irq, sixlinux_rtc_irq,
                           0, "sixlinux_rtc", rtc);
    if (ret)
        return dev_err_probe(&pdev->dev, ret, "failed to request IRQ %d\n",
                             rtc->irq);

    rtc->id = readl(rtc->base + RTC_PID0) |
              (readl(rtc->base + RTC_PID1) << 8) |
              (readl(rtc->base + RTC_PID2) << 16) |
              (readl(rtc->base + RTC_PID3) << 24);

    writel(RTC_CR_EN, rtc->base + RTC_CR);
    rtc->data = readl(rtc->base + RTC_DR);

    rtc->debugfs_dir = debugfs_create_dir("sixlinux_rtc", NULL);
    debugfs_create_u32("id", 0444, rtc->debugfs_dir, &rtc->id);
    debugfs_create_u32("data", 0444, rtc->debugfs_dir, &rtc->data);
    debugfs_create_u32("irq_count", 0444, rtc->debugfs_dir, &rtc->irq_count);
    debugfs_create_file("trigger", 0222, rtc->debugfs_dir, rtc,
                        &sixlinux_rtc_trigger_fops);

    rtc->rtc_dev = devm_rtc_allocate_device(&pdev->dev);
    if (IS_ERR(rtc->rtc_dev))
        return PTR_ERR(rtc->rtc_dev);
    rtc->rtc_dev->ops = &sixlinux_rtc_ops;

    ret = devm_rtc_register_device(rtc->rtc_dev);
    if (ret)
        return dev_err_probe(&pdev->dev, ret,
                             "failed to register RTC device\n");

    sixlinux_rtc_arm_alarm(rtc);

    dev_info(&pdev->dev, "SixLinux RTC probed: id=0x%08x irq=%d data=%u\n",
             rtc->id, rtc->irq, rtc->data);
    return 0;
}

static int sixlinux_rtc_remove(struct platform_device *pdev)
{
    struct sixlinux_rtc *rtc = platform_get_drvdata(pdev);

    writel(0, rtc->base + RTC_IMSC);
    debugfs_remove_recursive(rtc->debugfs_dir);
    return 0;
}

static const struct of_device_id sixlinux_rtc_of_match[] = {
    { .compatible = "arm,pl031" },
    { }
};
MODULE_DEVICE_TABLE(of, sixlinux_rtc_of_match);

static struct platform_driver sixlinux_rtc_driver = {
    .probe = sixlinux_rtc_probe,
    .remove = sixlinux_rtc_remove,
    .driver = {
        .name = "sixlinux_rtc",
        .of_match_table = sixlinux_rtc_of_match,
    },
};
module_platform_driver(sixlinux_rtc_driver);

MODULE_AUTHOR("SixLinux Project");
MODULE_DESCRIPTION("SixLinux PL031 RTC MMIO/IRQ platform driver");
MODULE_LICENSE("GPL");
