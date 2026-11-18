#!/usr/bin/env python3
"""Converts the OpenCV Model Zoo SFace face-embedding model to Core ML.

Pipeline: ONNX (pinned commit, SHA-256 checked) -> PyTorch (onnx2torch) -> TorchScript trace
-> Core ML ML Program (.mlpackage) with an image input and a float32 output named "embedding".

Run on a Linux or macOS host with Python 3.12:

    uv venv --python 3.12 .venv
    uv pip install --python .venv/bin/python --index-strategy unsafe-best-match \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        torch onnx onnxruntime onnx2torch coremltools numpy
    .venv/bin/python Scripts/convert-sface.py --precision float16

Outputs, relative to the project root unless overridden:

    HomePad/Models/FaceEmbedder.mlpackage      the converted model
    Scripts/face-model-fixtures/*.png           fixed test inputs
    Scripts/face-model-fixtures/reference.json  ONNX Runtime embeddings for those inputs
    <work-dir>/conversion-report.json           versions, hashes, and similarity numbers

The script cannot run the Core ML model (prediction needs macOS). Run
Scripts/verify-face-model.swift on a Mac to check the converted package against reference.json.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import platform
import struct
import sys
import urllib.request
import zlib
from pathlib import Path

import numpy as np

UPSTREAM_REPOSITORY = "https://github.com/opencv/opencv_zoo"
UPSTREAM_COMMIT = "48b10fa505aeb51fbd127fc60a5c660040e823b7"
UPSTREAM_PATH = "models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
ONNX_URL = f"{UPSTREAM_REPOSITORY}/raw/{UPSTREAM_COMMIT}/{UPSTREAM_PATH}"
ONNX_SHA256 = "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
ONNX_SIZE_BYTES = 38_696_353
LICENSE_NAME = "Apache-2.0"

INPUT_SIDE = 112
EMBEDDING_DIMENSION = 128
RANDOM_FIXTURE_COUNT = 8
RANDOM_SEED_BASE = 20211200
MINIMUM_HOST_COSINE = 0.9999

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def sha256_of_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_onnx(path: Path) -> None:
    """Downloads the pinned ONNX file when absent, then checks size and SHA-256."""
    if not path.exists():
        print(f"downloading {ONNX_URL}")
        with urllib.request.urlopen(ONNX_URL, timeout=120) as response:
            path.write_bytes(response.read())
    size = path.stat().st_size
    if size < 1024 and path.read_bytes().startswith(b"version https://git-lfs"):
        raise SystemExit(f"{path} is a Git LFS pointer, not the model binary")
    if size != ONNX_SIZE_BYTES:
        raise SystemExit(f"{path} is {size} bytes, expected {ONNX_SIZE_BYTES}")
    actual = sha256_of_file(path)
    if actual != ONNX_SHA256:
        raise SystemExit(f"{path} SHA-256 is {actual}, expected {ONNX_SHA256}")
    print(f"onnx ok: {size} bytes, sha256 {actual}")


def make_fixtures() -> list[tuple[str, np.ndarray]]:
    """Returns (name, HxWx3 uint8 RGB) test images. None of them is a face."""
    fixtures: list[tuple[str, np.ndarray]] = []
    for index in range(RANDOM_FIXTURE_COUNT):
        generator = np.random.default_rng(RANDOM_SEED_BASE + index)
        pixels = generator.integers(0, 256, size=(INPUT_SIDE, INPUT_SIDE, 3), dtype=np.uint8)
        fixtures.append((f"random-{index}", pixels))
    fixtures.append(("gray-128", np.full((INPUT_SIDE, INPUT_SIDE, 3), 128, dtype=np.uint8)))
    ramp = np.linspace(0, 255, INPUT_SIDE).round().astype(np.uint8)
    gradient = np.empty((INPUT_SIDE, INPUT_SIDE, 3), dtype=np.uint8)
    gradient[..., 0] = ramp[np.newaxis, :]
    gradient[..., 1] = ramp[:, np.newaxis]
    gradient[..., 2] = 64
    fixtures.append(("gradient", gradient))
    return fixtures


def write_png(path: Path, rgb: np.ndarray) -> None:
    """Writes an 8-bit RGB PNG with no color profile chunk, so decoders return the bytes as is."""
    height, width, channels = rgb.shape
    if channels != 3 or rgb.dtype != np.uint8:
        raise ValueError("expected an HxWx3 uint8 array")

    def chunk(kind: bytes, data: bytes) -> bytes:
        checksum = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)

    rows = b"".join(b"\x00" + rgb[row].tobytes() for row in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b"")
    )


def to_network_input(rgb: np.ndarray) -> np.ndarray:
    """HxWx3 uint8 RGB -> 1x3xHxW float32, RGB plane order, raw 0 to 255 values.

    This is what cv::dnn::blobFromImage(img, 1, Size(112, 112), Scalar(0, 0, 0), true, false)
    produces from a BGR cv::Mat in FaceRecognizerSF::feature.
    """
    return rgb.astype(np.float32).transpose(2, 0, 1)[np.newaxis, ...].copy()


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    a = a.astype(np.float64).ravel()
    b = b.astype(np.float64).ravel()
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def describe_onnx(onnx_path: Path) -> dict:
    """Reads the graph facts the input contract depends on, and fails if they changed."""
    import onnx
    from onnx import numpy_helper

    model = onnx.load(str(onnx_path))
    onnx.checker.check_model(model)
    graph = model.graph
    initializers = {item.name: item for item in graph.initializer}
    inputs = [item for item in graph.input if item.name not in initializers]
    if len(inputs) != 1 or len(graph.output) != 1:
        raise SystemExit("expected exactly one graph input and one graph output")

    def shape_of(value) -> list[int]:
        return [dimension.dim_value for dimension in value.type.tensor_type.shape.dim]

    input_shape = shape_of(inputs[0])
    output_shape = shape_of(graph.output[0])
    if input_shape != [1, 3, INPUT_SIDE, INPUT_SIDE]:
        raise SystemExit(f"unexpected input shape {input_shape}")
    if output_shape != [1, EMBEDDING_DIMENSION]:
        raise SystemExit(f"unexpected output shape {output_shape}")

    first, second = graph.node[0], graph.node[1]
    if first.op_type != "Sub" or second.op_type != "Mul":
        raise SystemExit("expected the graph to start with Sub then Mul (built-in normalization)")
    subtrahend = float(numpy_helper.to_array(initializers[first.input[1]]).ravel()[0])
    multiplier = float(numpy_helper.to_array(initializers[second.input[1]]).ravel()[0])
    return {
        "input_name": inputs[0].name,
        "input_shape": input_shape,
        "output_name": graph.output[0].name,
        "output_shape": output_shape,
        "opset": [(item.domain, item.version) for item in model.opset_import],
        "in_graph_normalization": {"subtract": subtrahend, "multiply": multiplier},
        "node_count": len(graph.node),
    }


def onnx_embeddings(onnx_path: Path, inputs: list[np.ndarray]) -> list[np.ndarray]:
    import onnxruntime

    session = onnxruntime.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    return [session.run(None, {input_name: item})[0][0] for item in inputs]


def newest_ios_target():
    import coremltools as ct

    ios_targets = [target for target in ct.target if target.name.startswith("iOS")]
    return max(ios_targets, key=lambda target: int(target.name[3:]))


def convert_to_coreml(traced, precision: str, output: Path):
    import coremltools as ct

    target = newest_ios_target()
    compute_precision = ct.precision.FLOAT16 if precision == "float16" else ct.precision.FLOAT32
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, INPUT_SIDE, INPUT_SIDE),
                color_layout=ct.colorlayout.RGB,
                scale=1.0,
                bias=[0.0, 0.0, 0.0],
            )
        ],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        minimum_deployment_target=target,
        compute_precision=compute_precision,
    )
    model.author = "Yaoyao Zhong and OpenCV Model Zoo contributors; Core ML conversion for HomePad"
    model.license = LICENSE_NAME
    model.version = "sface-2021dec"
    model.short_description = (
        "SFace face embedding (MobileFaceNet trained with the SFace loss). Input: a 112x112 face crop "
        "aligned to the five-point template used by OpenCV FaceRecognizerSF. Output: an unnormalized "
        "128-dimensional embedding. L2-normalize before comparing."
    )
    model.input_description["image"] = (
        "Aligned 112x112 color face crop. The model reads RGB with raw 0 to 255 values and "
        "normalizes internally."
    )
    model.output_description["embedding"] = (
        "128 float32 values, not L2-normalized. Same values as the ONNX output fc1."
    )
    model.user_defined_metadata["source_url"] = f"{UPSTREAM_REPOSITORY}/tree/{UPSTREAM_COMMIT}/models/face_recognition_sface"
    model.user_defined_metadata["source_commit"] = UPSTREAM_COMMIT
    model.user_defined_metadata["source_sha256"] = ONNX_SHA256
    model.user_defined_metadata["weight_precision"] = precision
    if output.exists():
        import shutil

        shutil.rmtree(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(output))
    return target


def package_weight_file(package: Path) -> Path:
    return package / "Data" / "com.apple.CoreML" / "weights" / "weight.bin"


def directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def tool_versions() -> dict:
    from importlib import metadata

    packages = ["numpy", "onnx", "onnxruntime", "onnx2torch", "torch", "torchvision", "coremltools"]
    versions = {"python": platform.python_version(), "platform": platform.platform()}
    for package in packages:
        try:
            versions[package] = metadata.version(package)
        except metadata.PackageNotFoundError:
            versions[package] = "not installed"
    return versions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work-dir", type=Path, default=PROJECT_ROOT / ".build" / "face-model-work")
    parser.add_argument("--output", type=Path, default=PROJECT_ROOT / "HomePad" / "Models" / "FaceEmbedder.mlpackage")
    parser.add_argument("--fixtures-dir", type=Path, default=PROJECT_ROOT / "Scripts" / "face-model-fixtures")
    parser.add_argument("--precision", choices=["float16", "float32"], default="float16")
    arguments = parser.parse_args()

    import torch
    from onnx2torch import convert as onnx_to_torch

    arguments.work_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = arguments.work_dir / "face_recognition_sface_2021dec.onnx"
    fetch_onnx(onnx_path)
    graph_facts = describe_onnx(onnx_path)
    print(f"graph: {json.dumps(graph_facts)}")

    fixtures = make_fixtures()
    network_inputs = [to_network_input(pixels) for _, pixels in fixtures]
    references = onnx_embeddings(onnx_path, network_inputs)

    torch.manual_seed(0)
    torch_model = onnx_to_torch(str(onnx_path)).eval()
    with torch.no_grad():
        traced = torch.jit.trace(torch_model, torch.from_numpy(network_inputs[0]), check_trace=True)
        traced_outputs = [traced(torch.from_numpy(item)).numpy()[0] for item in network_inputs]

    host_checks = []
    for (name, _), reference, candidate in zip(fixtures, references, traced_outputs):
        similarity = cosine(reference, candidate)
        max_abs_difference = float(np.max(np.abs(reference - candidate)))
        host_checks.append({"fixture": name, "cosine": similarity, "max_abs_difference": max_abs_difference})
        print(f"onnxruntime vs traced torch  {name:<10} cosine {similarity:.9f}  max abs diff {max_abs_difference:.3e}")
    worst = min(item["cosine"] for item in host_checks)
    if worst <= MINIMUM_HOST_COSINE:
        raise SystemExit(f"traced PyTorch module diverges from ONNX Runtime: worst cosine {worst}")

    arguments.fixtures_dir.mkdir(parents=True, exist_ok=True)
    reference_entries = []
    for (name, pixels), reference in zip(fixtures, references):
        write_png(arguments.fixtures_dir / f"{name}.png", pixels)
        reference_entries.append(
            {
                "file": f"{name}.png",
                "rgb_sha256": hashlib.sha256(pixels.tobytes()).hexdigest(),
                "embedding": [float(value) for value in reference],
            }
        )
    reference_document = {
        "model": Path(UPSTREAM_PATH).name,
        "onnx_sha256": ONNX_SHA256,
        "reference_runtime": "onnxruntime CPUExecutionProvider",
        "input": {"width": INPUT_SIDE, "height": INPUT_SIDE, "channel_order": "RGB", "value_range": [0, 255]},
        "embedding_dimension": EMBEDDING_DIMENSION,
        "fixtures": reference_entries,
    }
    (arguments.fixtures_dir / "reference.json").write_text(json.dumps(reference_document, indent=1) + "\n")

    target = convert_to_coreml(traced, arguments.precision, arguments.output)
    weight_file = package_weight_file(arguments.output)
    report = {
        "converted_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_url": ONNX_URL,
        "source_commit": UPSTREAM_COMMIT,
        "onnx_sha256": ONNX_SHA256,
        "onnx_size_bytes": ONNX_SIZE_BYTES,
        "graph": graph_facts,
        "precision": arguments.precision,
        "minimum_deployment_target": target.name,
        "package": arguments.output.name,
        "package_size_bytes": directory_size(arguments.output),
        "weight_file": str(weight_file.relative_to(arguments.output)),
        "weight_file_size_bytes": weight_file.stat().st_size,
        "weight_file_sha256": sha256_of_file(weight_file),
        "host_checks": host_checks,
        "host_worst_cosine": worst,
        "tool_versions": tool_versions(),
    }
    report_path = arguments.work_dir / f"conversion-report-{arguments.precision}.json"
    report_path.write_text(json.dumps(report, indent=1) + "\n")
    print(f"wrote {arguments.output} ({report['package_size_bytes']} bytes, target {target.name}, {arguments.precision})")
    print(f"weight file sha256 {report['weight_file_sha256']}")
    print(f"report {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
