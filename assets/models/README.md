# Document segmentation model

`document_seg.onnx` is **not** committed to the repo (it is ~95 MB FP32). Place it
here and it is picked up by `lib/services/document_segmenter.dart`.

## Generating the model

```bash
pip install torch segmentation-models-pytorch onnx onnxruntime
python tool/export_document_model.py --weights /path/to/midv500-checkpoint.pth
```

Weights come from the
[ternaus/midv-500-models](https://github.com/ternaus/midv-500-models) release
(config `2020-05-19.yaml`, U-Net + resnet34, 1 class).

Add `--fp16` for a ~48 MB half-precision export, or `--int8` for a dynamically
quantized copy.

## Contract

| | |
|---|---|
| Input | `input`, float32 NCHW `[1, 3, 512, 512]`, RGB, normalized with ImageNet mean/std |
| Output | `mask`, float32 `[1, 1, 512, 512]`, sigmoid already applied (values 0..1) |
| Threshold | 0.5 |

If the file is missing, `DocumentSegmenter.load()` returns `false` and the app
silently keeps using the native detector — the ONNX path is an optional
fallback.
