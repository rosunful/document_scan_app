#!/usr/bin/env python3
"""Export the MIDV-500 document segmentation U-Net to ONNX.

The app ships a single ONNX file at ``assets/models/document_seg.onnx``. It is a
U-Net (resnet34 encoder, 1 class) trained on MIDV-500 by the
`ternaus/midv-500-models <https://github.com/ternaus/midv-500-models>`_ project.

Why this script rebuilds the network instead of using the original repo's
``get_model(CONFIG_PATH)`` helper:

* the original training config pins 2020-era dependencies that are painful to
  install, and its inference script wraps the model in ``nn.Sequential(model,
  nn.Sigmoid())`` — we fuse the sigmoid here so the app can use a plain 0.5
  threshold;
* the original config uses 512x512 crops; we export a flat 512x512 so the Dart
  pre/post-processing is trivial (letterboxing is intentionally omitted, a
  square resize is fine for corner regression).

Usage
-----
::

    pip install torch segmentation-models-pytorch onnx onnxruntime
    python tool/export_document_model.py --weights path/to/checkpoint.pth

Get the weights/config from the model zoo release, e.g.
``2020-05-19.yaml`` and the matching ``.pth`` checkpoint.

Options
-------
--fp16   export a half-precision model (~48 MB instead of ~95 MB)
--int8   also write a dynamically quantized int8 copy (conv-heavy U-Nets often
         do NOT shrink with dynamic quantization; prefer --fp16 unless you
         measure otherwise)
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
import torch.nn as nn

INPUT_SIZE = 512
IMAGE_MEAN = (0.485, 0.456, 0.406)
IMAGE_STD = (0.229, 0.224, 0.225)


def build_model() -> nn.Module:
    import segmentation_models_pytorch as smp

    return smp.Unet(
        encoder_name="resnet34",
        encoder_weights=None,
        in_channels=3,
        classes=1,
    )


def load_weights(model: nn.Module, weights: Path) -> None:
    checkpoint = torch.load(str(weights), map_location="cpu")
    if isinstance(checkpoint, dict):
        for key in ("state_dict", "model", "model_state_dict"):
            if key in checkpoint:
                checkpoint = checkpoint[key]
                break

    cleaned = {}
    for key, value in checkpoint.items():
        for prefix in ("model.", "net.", "module.", "model.model."):
            if key.startswith(prefix):
                key = key[len(prefix) :]
        cleaned[key] = value

    missing, unexpected = model.load_state_dict(cleaned, strict=False)
    if missing:
        print(f"  ! {len(missing)} missing keys (e.g. {missing[:3]})")
    if unexpected:
        print(f"  ! {len(unexpected)} unexpected keys (e.g. {unexpected[:3]})")
    if not missing and not unexpected:
        print("  weights loaded cleanly")


def export(args: argparse.Namespace) -> None:
    torch.manual_seed(0)

    model = build_model()
    print(f"loading weights from {args.weights}")
    load_weights(model, args.weights)

    model = nn.Sequential(model, nn.Sigmoid())
    model.eval()

    dummy = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    if args.fp16:
        model = model.half()
        dummy = dummy.half()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with torch.no_grad():
        torch.onnx.export(
            model,
            dummy,
            str(args.output),
            input_names=["input"],
            output_names=["mask"],
            opset_version=12,
            dynamic_axes=None,
            do_constant_folding=True,
        )
    print(f"wrote {args.output} ({args.output.stat().st_size / 1e6:.1f} MB)")

    if args.int8:
        try:
            from onnxruntime.quantization import QuantType, quantize_dynamic
        except ImportError as exc:  # pragma: no cover - optional dependency
            raise SystemExit(
                "install onnxruntime to use --int8: pip install onnxruntime"
            ) from exc

        if args.fp16:
            print("skipping --int8 (dynamic quantization expects an fp32 model)")
            return

        int8_path = args.output.with_name(args.output.stem + "_int8.onnx")
        quantize_dynamic(str(args.output), str(int8_path), weight_type=QuantType.QInt8)
        print(
            f"wrote {int8_path} ({int8_path.stat().st_size / 1e6:.1f} MB)\n"
            "note: U-Net is conv-dominated; dynamic int8 quantizes mostly the "
            "decoder/head matmuls, so the size win may be small."
        )


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--weights",
        required=True,
        type=Path,
        help="path to the MIDV-500 checkpoint (.pth)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "assets" / "models" / "document_seg.onnx",
        help="destination ONNX path",
    )
    parser.add_argument("--fp16", action="store_true", help="export half precision")
    parser.add_argument(
        "--int8",
        action="store_true",
        help="also write a dynamically quantized int8 copy",
    )
    export(parser.parse_args())


if __name__ == "__main__":
    main()
