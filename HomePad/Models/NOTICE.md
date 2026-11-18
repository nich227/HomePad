# FaceEmbedder.mlpackage: third-party notice

`FaceEmbedder.mlpackage` is a Core ML conversion of the SFace face recognition model from the
OpenCV Model Zoo. It is a modified form of the upstream file (format conversion and weight
precision change, described under "Changes from the upstream file").

## Source

| Item | Value |
|---|---|
| Model | SFace (MobileFaceNet trained with the SFace loss), contributed to the OpenCV Model Zoo by Yaoyao Zhong, ONNX conversion by Chengrui Wang |
| Directory | https://github.com/opencv/opencv_zoo/tree/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_recognition_sface |
| File | `face_recognition_sface_2021dec.onnx` |
| Download URL | https://github.com/opencv/opencv_zoo/raw/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_recognition_sface/face_recognition_sface_2021dec.onnx |
| Upstream commit read and downloaded from | `48b10fa505aeb51fbd127fc60a5c660040e823b7` (`main` on 2026-11-17) |
| Commit that last changed the ONNX file | `ba91a3b91d00d76e86540d4013f944bd6b514e39` (2022-01-06) |
| Original file size | 38,696,353 bytes |
| Original file SHA-256 | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` |

The SHA-256 of the downloaded binary equals the `oid sha256` in the Git LFS pointer stored in the
repository at that commit, and the size equals the pointer's `size`.

## License

Apache License 2.0. Read on 2026-11-17 at the commit above, in three places:

1. `models/face_recognition_sface/LICENSE` is the full Apache License, Version 2.0, January 2004
   text (11,358 bytes, SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`).
   It is reproduced at the end of this file.
2. `models/face_recognition_sface/README.md`, section "License":

   > All files in this directory are licensed under [Apache 2.0 License](./LICENSE).

3. The repository `README.md`, section "License", and the repository `LICENSE` (also the Apache
   License 2.0 text):

   > OpenCV Zoo is licensed under the [Apache 2.0 license](./LICENSE). Please refer to licenses of different models.

Copyright line in `sface.py` in the same directory:

> Copyright (C) 2021, Shenzhen Institute of Artificial Intelligence and Robotics for Society, all rights reserved.
> Third party copyrights are property of their respective owners.

The upstream repository has no `NOTICE` file at the root or in the model directory.

Not verified: the original training code repository that the zoo README credits
(https://github.com/zhongyy/SFace) has no license file, and the zoo README does not say which
dataset this checkpoint was trained on. The license statement above covers the files as
distributed in the OpenCV Model Zoo directory.

## Changes from the upstream file

- Converted from ONNX to a Core ML ML Program (`.mlpackage`) through PyTorch.
- Weights stored as float16 (upstream is float32), and the program computes in float16.
- The input is a Core ML image feature named `image` instead of a float tensor named `data`.
- The output is renamed from `fc1` to `embedding`.
- No retraining, pruning, or change to the network structure. The normalization that the ONNX
  graph does on its input (subtract 127.5, multiply by 0.0078125) is kept inside the model.

## Converted package

| Item | Value |
|---|---|
| Conversion date | 2026-11-17 (19:13:20 UTC) |
| Conversion host | axedesk, Amazon Linux 2023, x86_64 |
| Script | `Scripts/convert-sface.py --precision float16` |
| Package size | 19,346,327 bytes |
| Weight file | `Data/com.apple.CoreML/weights/weight.bin`, 19,296,256 bytes |
| Weight file SHA-256 | `97b7c06ffa35068a66418e3d8df60ef511d480775cc2eb6f80cf219e56c6267a` |
| Model type | ML Program, specification version 10, minimum deployment target `iOS26` in coremltools |
| Weight precision | float16 |

Tool versions on the conversion host: Python 3.12.13, uv 0.11.30, coremltools 9.0,
torch 2.15.0+cpu, onnx2torch 1.5.15, onnx 1.23.2, onnxruntime 1.32.0, numpy 2.5.5. Installed as
dependencies of those: torchvision 0.29.2+cpu, pillow 13.0.0. coremltools 9.0 warns that it has
not been tested with torch newer than 2.7.0. The numerical checks in `docs/FACE_MODEL.md` are what
shows the conversion is correct.

Verification on the Mac: macOS 26.7.3, Xcode 27.2, Swift 6.4.2, Apple M3 Pro.

## Input and output contract

| Item | Value |
|---|---|
| Input name | `image` |
| Input type | Color image, exactly 112 x 112 pixels |
| Pixel buffer formats | `kCVPixelFormatType_32BGRA` (verified) |
| Channel order seen by the network | RGB. Core ML maps the pixel buffer channels to RGB. |
| Value range | Raw 0 to 255. Do not scale or subtract a mean before calling the model. |
| Normalization | Inside the model: `(x - 127.5) * 0.0078125` |
| Expected content | A face crop aligned to the five-point template in `docs/FACE_MODEL.md` |
| Output name | `embedding` |
| Output type | `MLMultiArray`, float32, shape `[1, 128]` |
| Output normalization | None. L2-normalize both embeddings before comparing. |

Match thresholds on L2-normalized embeddings, from `sface.py` in the model directory
(`_threshold_cosine = 0.363`, `_threshold_norml2 = 1.128`) and the LFW row of the table in the
OpenCV tutorial `doc/tutorials/dnn/dnn_face/dnn_face.markdown`:

- Same person when cosine similarity is greater than or equal to 0.363.
- Same person when the L2 distance is less than or equal to 1.128.

The two thresholds are the same decision: for unit vectors, distance squared is 2 - 2 x cosine,
and 2 - 2 x 0.363 = 1.274, whose square root is 1.129.

## Apache License 2.0 (verbatim from the upstream model directory)

```

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

```
