# NPU smoke test kit — hardware test matrix row 17

Self-contained kit to prove the NPU works on a candidate image. Everything the
tablet needs is in this directory.

## Contents

| File | What |
|---|---|
| `mobilenet_v2_rk3562.rknn` | MobileNetV2 (fp16, no quantization) converted for rk3562 — from `onnx/models` mobilenetv2-12.onnx |
| `convert_mobilenet.py` | The exact conversion script that produced it (runs on Conrad in the rknn venv) |
| `conversion-env-pins.txt` | Working Conrad venv pins (see gotchas below) |
| `rknn_toolkit_lite2-2.3.2-cp311-*.whl` | Device-side Python inference wheel (Bookworm = Python 3.11) |
| `npu_smoke_test.py` | Loads the model, inits runtime, times 50 inferences |
| `run-smoke-test.sh` | Orchestrates everything and writes evidence to `./evidence/<timestamp>/` |

## On the tablet

```bash
# one-time setup (librknnrt deb is in ../../..//debs/)
sudo apt install ./librknnrt_2.3.2-1_arm64.deb
pip3 install --break-system-packages ./rknn_toolkit_lite2-2.3.2-cp311-*.whl

# run (captures driver version, devfreq, load before/during/after, timings)
./run-smoke-test.sh
```

PASS = runtime initializes and 50 inferences complete. The script also
captures `/sys/kernel/debug/rknpu/load` idle vs. mid-run, answering the
"is NPU load reporting live or static?" question (wiki 06, open question 1).

## Rebuilding the model on Conrad

```bash
source ~/venvs/rknn/bin/activate   # created per scripts/setup-rknn-conversion-env.sh
python convert_mobilenet.py        # needs mobilenetv2-12.onnx alongside
```

### Conversion-environment gotchas (hit and solved 2026-07-04)

- `setuptools<81` required — v81 removed `pkg_resources`, which
  rknn-toolkit2 2.3.2 imports at startup.
- `onnx==1.16.1` — newer onnx removed `onnx.mapping`, which the toolkit uses.
  (Rockchip's own `requirements_cp312-2.3.2.txt` says `onnx>=1.16.1`; treat it
  as `==1.16.1`.)
- The ONNX zoo model has a dynamic batch dim: pass
  `inputs=['input'], input_size_list=[[1,3,224,224]]` to `load_onnx`.
- fp16 (`do_quantization=False`) is deliberate for the smoke test — no
  calibration dataset needed. Real workloads should use INT8 (wiki 05).
