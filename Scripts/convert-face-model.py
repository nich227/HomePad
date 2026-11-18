#!/usr/bin/env python3
"""Convert a face embedding model to FaceEmbedder.mlpackage for HomePad.

This script has not been run. It documents the conversion a developer does once, on their own
machine, for a model they are licensed to use. HomePad already bundles SFace, which is converted
by Scripts/convert-sface.py. Use this script only to try a different model.

LICENSING. Check the license of the weights before you convert them, not only the license of the
code that defines the network. Many public face recognition weights are limited to non-commercial
research use. That includes most InsightFace model packs (the "buffalo" and "antelope" sets) and
many ArcFace checkpoints trained on MS1M or Glint360K. Training-set terms can restrict a model
even when its repository carries a permissive license. Record what you checked next to the model,
the way HomePad/Models/NOTICE.md does for SFace.

WHAT THE APP EXPECTS. CoreMLFaceEmbedder accepts any model with
  - one image input (square, color), or one image-shaped float tensor input, and
  - one float vector output.
An image input is simpler and is what this script produces. The pixel normalization is baked into
the model, so the app passes a plain 32BGRA pixel buffer and does no scaling of its own. The app
L2-normalizes the output, so the model does not have to.

SETUP (do this yourself, the script installs nothing):
    python3 -m venv .venv
    .venv/bin/pip install coremltools torch            # for a PyTorch model
    .venv/bin/pip install coremltools tensorflow       # for a TensorFlow or Keras model

EXAMPLES
  A TorchScript file whose network wants RGB values in -1...1 (ArcFace and MobileFaceNet style):
    .venv/bin/python Scripts/convert-face-model.py \\
        --framework torch --input mobilefacenet.torchscript.pt \\
        --size 112 --normalization signed-unit --license "MIT" --source "https://example.com/model"

  A Keras FaceNet model that wants RGB values in 0...1 at 160 x 160:
    .venv/bin/python Scripts/convert-face-model.py \\
        --framework tensorflow --input facenet_keras.h5 \\
        --size 160 --normalization unit-range --license "MIT" --source "https://example.com/model"

NORMALIZATION. Core ML applies `value * scale + bias` per channel to the 0...255 pixel values:
    signed-unit   (x - 127.5) / 127.5      scale 1/127.5, bias -1
    signed-128    (x - 127.5) / 128        scale 1/128,   bias -127.5/128
    unit-range    x / 255                  scale 1/255,   bias 0
    raw           x                        scale 1,       bias 0
A model that needs a different deviation per channel (ImageNet statistics) cannot be expressed as
one scale. Wrap the network in a module that divides by the deviation, or keep a tensor input and
set EmbedderPreprocessing.imageNet in the app.

AFTER CONVERTING
  1. Compare the Core ML output with the original framework's output on a few aligned face crops.
     A cosine similarity below 0.999 means the preprocessing or channel order is wrong.
  2. Add the package to the app target and set its code generation language to None in Xcode, so
     that no class named FaceEmbedder is generated.
  3. Calibrate a MatchPolicy for the model. See docs/FACE_RECOGNITION.md.
"""

import argparse
import sys

NORMALIZATIONS = {
    "signed-unit": (1.0 / 127.5, -1.0),
    "signed-128": (1.0 / 128.0, -127.5 / 128.0),
    "unit-range": (1.0 / 255.0, 0.0),
    "raw": (1.0, 0.0),
}


def parse_arguments():
    parser = argparse.ArgumentParser(description="Convert a face embedding model to Core ML.")
    parser.add_argument("--framework", choices=["torch", "tensorflow"], required=True)
    parser.add_argument("--input", required=True, help="TorchScript file, SavedModel directory, or Keras .h5 file")
    parser.add_argument("--output", default="FaceEmbedder.mlpackage")
    parser.add_argument("--size", type=int, default=112, help="side of the square input crop in pixels")
    parser.add_argument("--normalization", choices=sorted(NORMALIZATIONS), default="signed-unit")
    parser.add_argument("--channel-order", choices=["RGB", "BGR"], default="RGB",
                        help="channel order the network was trained on")
    parser.add_argument("--output-name", default="embedding", help="name for the Core ML output feature")
    parser.add_argument("--precision", choices=["float16", "float32"], default="float16")
    parser.add_argument("--license", required=True, help="license of the weights, recorded in the model metadata")
    parser.add_argument("--source", required=True, help="where the weights came from, recorded in the model metadata")
    return parser.parse_args()


def load_torch(path, size):
    import torch

    module = torch.jit.load(path, map_location="cpu")
    module.eval()
    example = torch.rand(1, 3, size, size)
    # Tracing fixes the input shape, which Core ML needs for an image input.
    return torch.jit.trace(module, example), (1, 3, size, size)


def load_tensorflow(path, size):
    import tensorflow as tf

    if path.endswith((".h5", ".keras")):
        model = tf.keras.models.load_model(path, compile=False)
    else:
        # coremltools reads a SavedModel directory by path.
        model = path
    return model, (1, size, size, 3)


def main():
    arguments = parse_arguments()
    try:
        import coremltools as ct
    except ImportError:
        sys.exit("coremltools is not installed. See the setup section at the top of this file.")

    if arguments.framework == "torch":
        model, shape = load_torch(arguments.input, arguments.size)
        source = "pytorch"
    else:
        model, shape = load_tensorflow(arguments.input, arguments.size)
        source = "tensorflow"

    scale, bias = NORMALIZATIONS[arguments.normalization]
    color_layout = ct.colorlayout.RGB if arguments.channel_order == "RGB" else ct.colorlayout.BGR
    image_input = ct.ImageType(
        name="image",
        shape=shape,
        scale=scale,
        bias=[bias, bias, bias],
        color_layout=color_layout,
    )
    precision = ct.precision.FLOAT16 if arguments.precision == "float16" else ct.precision.FLOAT32

    converted = ct.convert(
        model,
        source=source,
        inputs=[image_input],
        outputs=[ct.TensorType(name=arguments.output_name)],
        convert_to="mlprogram",
        compute_precision=precision,
        minimum_deployment_target=ct.target.iOS18,
    )

    converted.short_description = (
        f"Face embedding model. Input: aligned {arguments.size} x {arguments.size} face crop. "
        f"Output: embedding vector, not normalized."
    )
    converted.license = arguments.license
    converted.user_defined_metadata["source"] = arguments.source
    converted.user_defined_metadata["normalization"] = arguments.normalization
    converted.user_defined_metadata["channelOrder"] = arguments.channel_order
    converted.save(arguments.output)

    specification = converted.get_spec()
    print(f"Wrote {arguments.output}")
    print("Inputs:", [feature.name for feature in specification.description.input])
    print("Outputs:", [feature.name for feature in specification.description.output])
    print("Next: compare its output with the original model, then calibrate a MatchPolicy.")


if __name__ == "__main__":
    main()
