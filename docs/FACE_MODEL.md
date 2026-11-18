# Face embedding model (FaceEmbedder)

`HomePad/Models/FaceEmbedder.mlpackage` turns an aligned 112 x 112 face crop into a 128-number
embedding. Two crops of the same person give embeddings that point in nearly the same direction.
The app loads it from the main bundle by the name `FaceEmbedder` (Xcode compiles the package to
`FaceEmbedder.mlmodelc` when the package is in the app target).

Licensing, hashes, and tool versions are in `HomePad/Models/NOTICE.md`.

## What it is

SFace from the OpenCV Model Zoo, file `face_recognition_sface_2021dec.onnx`: a MobileFaceNet
network (27 convolutions with PReLU, one fully connected layer) trained with the SFace loss. It is
the model behind `cv::FaceRecognizerSF` in OpenCV.

- Upstream: https://github.com/opencv/opencv_zoo/tree/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_recognition_sface
- Paper: https://ieeexplore.ieee.org/document/9318547

## Why this model

- The license is Apache-2.0, stated in the model directory itself. Many face recognition weights
  (for example the InsightFace `buffalo` packs) are limited to non-commercial research use and were
  ruled out for that reason.
- It is small: 19 MB as shipped, which suits an on-device hub.
- The preprocessing is simple and documented in code: RGB, raw 0 to 255 values, normalization
  inside the graph.
- OpenCV publishes match thresholds for it.

## Contract

| Item | Value | Where it was verified |
|---|---|---|
| Input | Image feature `image`, 112 x 112, color | `Size(112, 112)` in `FaceRecognizerSF::feature` and `alignCrop`; ONNX input shape `[1, 3, 112, 112]` |
| Channel order | RGB | `blobFromImage(..., swapRB = true, ...)` on OpenCV's BGR image |
| Value range | Raw 0 to 255, no mean | `blobFromImage(img, 1, Size(112, 112), Scalar(0, 0, 0), true, false)`: scale factor 1, mean 0 |
| Normalization | `(x - 127.5) * 0.0078125`, inside the model | First two nodes of the ONNX graph (`Sub`, `Mul`). The conversion script fails if they change. |
| Output | `embedding`, float32, shape `[1, 128]`, not normalized | ONNX output `fc1`, shape `[1, 128]`; `match` in OpenCV normalizes both features before comparing |
| Cosine threshold | Same person at 0.363 or above | `sface.py` in the model directory; LFW row of the OpenCV `dnn_face` tutorial |
| L2 threshold | Same person at 1.128 or below | Same two sources |

OpenCV source read: `modules/objdetect/src/face_recognize.cpp` at commit
`f4fa6371cb7e62db8271ba393e99ef5abcd6a2f3` (branch `4.x`, 2026-11-17).

The model zoo README for SFace does not list thresholds. They are constants in `sface.py` next to
it, and the OpenCV tutorial gives the table they come from:

| Database | Accuracy | Threshold (L2) | Threshold (cosine) |
|---|---|---|---|
| LFW | 99.60% | 1.128 | 0.363 |
| CALFW | 93.95% | 1.149 | 0.340 |
| CPLFW | 91.05% | 1.204 | 0.275 |
| AgeDB-30 | 94.90% | 1.202 | 0.277 |
| CFP-FP | 94.80% | 1.253 | 0.212 |

These are upstream numbers. None of them was measured here.

### Calling it

- Pass a `CVPixelBuffer` of exactly 112 x 112 pixels in `kCVPixelFormatType_32BGRA`. Do not
  convert to float, scale, or reorder channels. Core ML hands the network RGB.
- L2-normalize the output before comparing. Cosine similarity of two normalized embeddings is
  their dot product.
- The embedding is biometric data. The storage and logging rules in `docs/AGENT_BRIEF.md` apply
  to it.

### Alignment

The network expects the face warped so that five landmarks sit at fixed positions in the
112 x 112 crop. From `getSimilarityTransformMatrix` in `face_recognize.cpp`:

| Landmark | x | y |
|---|---|---|
| Right eye (the person's right, so the left side of the image) | 38.2946 | 51.6963 |
| Left eye | 73.5318 | 51.5014 |
| Nose tip | 56.0252 | 71.7366 |
| Right corner of the mouth | 41.5493 | 92.3655 |
| Left corner of the mouth | 70.7299 | 92.2041 |

OpenCV fits a similarity transform (rotation, uniform scale, translation, no shear) from the five
detected points to this template by least squares, then warps with bilinear interpolation
(`warpAffine(..., Size(112, 112), INTER_LINEAR)`). The landmark order is the one the YuNet detector
returns, documented on `FaceDetectorYN::detect` in `face.hpp`.

## Regenerate

The conversion needs Python 3.12 and about 1.2 GB of disk for the environment and working files. It ran on the Linux host
axedesk in `~/scratch/homepad-face-model`, which is still there.

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --index-strategy unsafe-best-match \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    torch onnx onnxruntime onnx2torch coremltools numpy
.venv/bin/python Scripts/convert-sface.py --precision float16
```

The script downloads the ONNX file from the pinned commit, checks its size and SHA-256, checks the
graph facts the contract depends on, compares ONNX Runtime against the traced PyTorch module,
writes the fixtures and `reference.json`, and writes the package. `--work-dir`, `--output`, and
`--fixtures-dir` override the default locations. The weight file is reproducible: two runs gave the
same SHA-256.

## Verify

```bash
tmp=$(mktemp -d)
xcrun coremlcompiler compile HomePad/Models/FaceEmbedder.mlpackage "$tmp"
swift Scripts/verify-face-model.swift "$tmp/FaceEmbedder.mlmodelc" Scripts/face-model-fixtures
swift Scripts/verify-face-model.swift "$tmp/FaceEmbedder.mlmodelc" Scripts/face-model-fixtures --compute-units cpu
rm -rf "$tmp"
```

The Swift script decodes each PNG, checks the SHA-256 of the decoded RGB bytes against
`reference.json` (so a decoder that alters pixels cannot hide behind a pass), fills a 32BGRA pixel
buffer, runs the model, and compares with the ONNX Runtime embedding. It exits 1 if any fixture is
at or below cosine 0.999.

`--swap-red-blue` puts red and blue in each other's slots. The check must then fail. If it still
passes, the test is not looking at channel order.

### Results on 2026-11-17

Fixtures: eight 112 x 112 images of uniform random noise from fixed seeds, one constant gray
image (128), and one color gradient. None is a face.

| Check | Where | Result |
|---|---|---|
| ONNX Runtime against the traced PyTorch module | axedesk | Cosine 1.0 on all 10 (largest shortfall 2.5e-12), largest element difference 2.4e-06 |
| Shipped float16 package against ONNX Runtime, compute units `all` | Mac, Apple M3 Pro | Cosine 0.999983 to 0.999996, relative L2 error 0.3% to 0.6% |
| Shipped float16 package against ONNX Runtime, compute units `cpu` | Mac | Cosine 0.999880 to 0.999941, relative L2 error 1.1% to 1.6% |
| Float32 package against ONNX Runtime (not shipped) | Mac | Cosine 1.000000 on all 10, both compute unit settings |
| Red and blue swapped on purpose | Mac | Fails: cosine 0.759 to 0.904 on the nine color fixtures. The gray fixture still passes, as it must, because swapping equal channels changes nothing. |

Float16 was shipped because it stays above the 0.999 bar on every fixture and halves the package
(19.3 MB against 38.6 MB).

The package also compiles with `xcrun coremlcompiler compile ... --platform ios --deployment-target 26.0`.
The compiled metadata reports specification version 10 and lists availability as iOS 19.0 and
macOS 16.0, while coremltools 9.0 names the same target `iOS26`. The package loaded and ran on
macOS 26.7.3.

## Limits

- **Recognition accuracy on real faces was not measured here.** The checks above show that the
  Core ML package computes the same function as the upstream ONNX file on noise, gray, and gradient
  images. They say nothing about how well it tells people apart. No face photos or datasets were
  downloaded.
- The float16 error was measured on those synthetic images only. It may differ on face crops.
- The thresholds assume OpenCV's pipeline: YuNet landmarks and the alignment above. Landmarks from
  another detector (for example Vision) sit at slightly different points, which shifts the crop
  and can shift the score distribution. Measure with the household's own enrollments before
  trusting 0.363, and treat the threshold as a setting.
- The published accuracy is on LFW-style benchmarks. It drops on the harder sets in the table
  (pose and age variation), and it is not broken down by age, gender, or skin tone. Expect more
  errors for children and for faces at steep angles or in poor light.
- The model has no liveness or anti-spoofing check. A photo or a screen showing an enrolled face
  produces a matching embedding. Since a face match unlocks personal content on the hub, this needs
  its own mitigation outside the model.
- The model was not run on an iPad or iPhone. It was compiled for iOS and run on macOS.
- The model does no detection or alignment. A crop that is not aligned gives a poor embedding
  without any error.
- The training dataset for this checkpoint is not stated in the model zoo README, and the original
  training code repository has no license file. See `HomePad/Models/NOTICE.md`.
- coremltools 9.0 has not been tested by its authors with torch 2.15.0. The numerical checks are
  the evidence that the conversion is correct.
