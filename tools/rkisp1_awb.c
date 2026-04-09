/* rkisp1_awb.c — persistent AWB gain feeder for rkisp1
 * Feeds AWB gain params in a loop while the ISP is streaming.
 * Run this as a background process alongside the camera stream.
 * Usage: ./rkisp1_awb [r gr gb b]  (Q8: 256=1.0x, defaults fit s5k5e8 daylight)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>
#include <linux/rkisp1-config.h>

#define PARAMS_DEV "/dev/video28"
#define NUM_BUFS   2

static volatile int running = 1;
static void sig_handler(int s) { (void)s; running = 0; }

int main(int argc, char *argv[]) {
    int r = 512, gr = 256, gb = 256, b = 640;
    if (argc == 5) { r=atoi(argv[1]); gr=atoi(argv[2]); gb=atoi(argv[3]); b=atoi(argv[4]); }

    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);

    int fd = open(PARAMS_DEV, O_RDWR);
    if (fd < 0) { perror("open"); return 1; }

    struct v4l2_format fmt = {0};
    fmt.type = V4L2_BUF_TYPE_META_OUTPUT;
    fmt.fmt.meta.dataformat = V4L2_META_FMT_RK_ISP1_PARAMS;
    fmt.fmt.meta.buffersize = sizeof(struct rkisp1_params_cfg);
    if (ioctl(fd, VIDIOC_S_FMT, &fmt) < 0) { perror("S_FMT"); return 1; }

    struct v4l2_requestbuffers req = {0};
    req.count = NUM_BUFS; req.type = V4L2_BUF_TYPE_META_OUTPUT; req.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd, VIDIOC_REQBUFS, &req) < 0) { perror("REQBUFS"); return 1; }

    void *maps[NUM_BUFS]; __u32 sizes[NUM_BUFS];
    for (int i = 0; i < NUM_BUFS; i++) {
        struct v4l2_buffer buf = {0};
        buf.type = V4L2_BUF_TYPE_META_OUTPUT; buf.memory = V4L2_MEMORY_MMAP; buf.index = i;
        if (ioctl(fd, VIDIOC_QUERYBUF, &buf) < 0) { perror("QUERYBUF"); return 1; }
        maps[i] = mmap(NULL, buf.length, PROT_READ|PROT_WRITE, MAP_SHARED, fd, buf.m.offset);
        sizes[i] = buf.length;
        if (maps[i] == MAP_FAILED) { perror("mmap"); return 1; }
    }

    int type = V4L2_BUF_TYPE_META_OUTPUT;
    if (ioctl(fd, VIDIOC_STREAMON, &type) < 0) { perror("STREAMON"); return 1; }

    /* Pre-fill both buffers and queue them */
    for (int i = 0; i < NUM_BUFS; i++) {
        struct rkisp1_params_cfg *p = (struct rkisp1_params_cfg *)maps[i];
        memset(p, 0, sizeof(*p));
        p->module_en_update  = RKISP1_CIF_ISP_MODULE_AWB_GAIN;
        p->module_ens        = RKISP1_CIF_ISP_MODULE_AWB_GAIN;
        p->module_cfg_update = RKISP1_CIF_ISP_MODULE_AWB_GAIN;
        p->others.awb_gain_config.gain_red     = (unsigned short)r;
        p->others.awb_gain_config.gain_green_r = (unsigned short)gr;
        p->others.awb_gain_config.gain_green_b = (unsigned short)gb;
        p->others.awb_gain_config.gain_blue    = (unsigned short)b;

        struct v4l2_buffer buf = {0};
        buf.type = V4L2_BUF_TYPE_META_OUTPUT; buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i; buf.bytesused = sizeof(*p);
        if (ioctl(fd, VIDIOC_QBUF, &buf) < 0) { perror("QBUF"); return 1; }
    }

    fprintf(stderr, "rkisp1_awb: R=%d Gr=%d Gb=%d B=%d running\n", r, gr, gb, b);

    /* Dequeue consumed buffers and requeue them to keep the ISP fed */
    while (running) {
        struct v4l2_buffer buf = {0};
        buf.type = V4L2_BUF_TYPE_META_OUTPUT; buf.memory = V4L2_MEMORY_MMAP;
        if (ioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
            if (running) perror("DQBUF");
            break;
        }
        /* Requeue with same AWB gains */
        buf.bytesused = sizeof(struct rkisp1_params_cfg);
        if (ioctl(fd, VIDIOC_QBUF, &buf) < 0) {
            if (running) perror("QBUF requeue");
            break;
        }
    }

    ioctl(fd, VIDIOC_STREAMOFF, &type);
    for (int i = 0; i < NUM_BUFS; i++) munmap(maps[i], sizes[i]);
    close(fd);
    fprintf(stderr, "rkisp1_awb: stopped\n");
    return 0;
}
