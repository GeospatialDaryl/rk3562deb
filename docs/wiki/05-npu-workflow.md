# 05 — NPU Development Workflow

The native-use pipeline once the image is validated: models are converted on
Conrad (x86), inference runs on samwise (ARM64, NPU). The RK3562's unit is
1 TOPS INT8 — quantized INT8 models are the intended payload.

## The stack, top to bottom

| Layer | Component | Where |
|---|---|---|
| Model conversion | `rknn-toolkit2` (Python, x86_64 only) | Conrad |
| Inference API (C/C++) | `librknnrt.so` — version **2.3.2** proven on this device | samwise |
| Inference API (Python) | `rknn-toolkit-lite2` (wraps librknnrt) | samwise |
| LLM runtime | RKLLM (`librkllmrt`) — needs driver ≥ 0.9.8 | samwise |
| Kernel driver | `rknpu` v0.9.8 (in-kernel, CONFIG_ROCKCHIP_RKNPU=y) | image |
| Hardware | `npu@ff300000` + IOMMU + `vdd_npu` rail | tablet |

Upstream sources: [airockchip/rknn-toolkit2](https://github.com/airockchip/rknn-toolkit2)
(toolkit, runtime binaries, C API headers, examples) and
[airockchip/rknn-llm](https://github.com/airockchip/rknn-llm) (RKLLM).
RK3562 is a supported target platform in both.

## Conversion on Conrad (typical flow)

```python
# pip install rknn-toolkit2  (x86_64 Linux; match the runtime's 2.3.x series)
from rknn.api import RKNN

rknn = RKNN()
rknn.config(target_platform='rk3562',
            mean_values=[[123.675, 116.28, 103.53]],
            std_values=[[58.395, 57.12, 57.375]])
rknn.load_onnx(model='model.onnx')            # also: load_tflite, load_pytorch
rknn.build(do_quantization=True, dataset='calib_images.txt')  # INT8 + calibration set
rknn.export_rknn('model.rknn')
```

Keep the toolkit's minor version aligned with the device runtime (2.3.x ↔
librknnrt 2.3.2). A model built by a much newer toolkit may demand a newer
runtime, which in turn can demand a newer kernel driver — the same version
contract that drove the 0.9.8 backport.

The toolkit also offers a **simulator** and, with the device connected/
reachable, on-target accuracy analysis and performance evaluation
(`rknn.eval_perf()`), useful before committing to a model.

## Inference on samwise

C API sketch (link `-lrknnrt`, headers from the rknn-toolkit2 repo):

```c
rknn_context ctx;
rknn_init(&ctx, model_data, model_size, 0, NULL);
rknn_inputs_set(ctx, io_num.n_input, inputs);
rknn_run(ctx, NULL);
rknn_outputs_get(ctx, io_num.n_output, outputs, NULL);
```

Python:

```python
from rknnlite.api import RKNNLite
rl = RKNNLite()
rl.load_rknn('model.rknn')
rl.init_runtime()
outputs = rl.inference(inputs=[img])
```

Validation runs should double as matrix row 17 evidence: capture the sample's
stdout and `sudo cat /sys/kernel/debug/rknpu/load` during inference.

## RKLLM

Small quantized LLMs (RK3562 support arrived in later RKLLM releases; the
stock system already runs it, so the capability is proven on this hardware).
Flow mirrors RKNN: convert/quantize on x86 with `rkllm-toolkit`, run on device
with `librkllmrt` + the `llm_demo` binary. This is matrix row 18. The driver
≥ 0.9.8 requirement is the binding constraint the backport satisfies.

## CPU fallback as correctness reference (D008)

Keep a CPU path (onnxruntime or XNNPACK-backed TFLite on the A53s) purely to
diff outputs against the NPU results when debugging quantization or runtime
issues. It is not a serving path — four A53s are no match for even 1 TOPS of
INT8 — and GPU (Mali-G52) inference is explicitly out of scope.

## Packaging the runtime (planned, per spec `NPU_RUNTIME: opt-in, separately versioned`)

The runtime must ship as versioned opt-in debs in the overlay (`rk3562deb`
`debs/` dir feeding image customization), **not** baked into the base image:

- `librknnrt` deb: `/usr/lib/librknnrt.so` (2.3.2 binary from the
  rknn-toolkit2 repo or captured from stock), C headers, and a known-good
  sample + model as a smoke test.
- RKLLM deb: `librkllmrt.so` + `llm_demo` + a small test model, versioned
  separately.

Until those debs exist, copying `/usr/lib/librknnrt.so` off the stock system
onto a candidate image is an acceptable interim for matrix row 17.
