# 第三方声明

## 规则来源

规则来源与实现范围见 [RULES.md](core/crates/deai-core/RULES.md)。

### lieflat-less-ai-tone

中文 AI 语气规则衍生自 [lieflat-less-ai-tone](https://github.com/larashero3-dotcom/lieflat-less-ai-tone)，采用 MIT 许可证。以下保留其许可证原文：

```text
MIT License

Copyright (c) 2026 shiujan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### blader/humanizer

英文 AI 语气正则规则衍生自 [blader/humanizer](https://github.com/blader/humanizer) 中适合用正则检测的规则，采用 MIT 许可证。以下原文来自其 [LICENSE](https://raw.githubusercontent.com/blader/humanizer/main/LICENSE)：

```text
MIT License

Copyright (c) 2025 Siqi Chen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Harper

英文语法检查使用 [Harper](https://github.com/automattic/harper) 的 `harper-core`，采用 Apache License 2.0。

`harper-core` 2.11.0 的 crates.io 源码包不含 `NOTICE` 文件。以下保留该版本对应上游提交的 [LICENSE 原文](https://github.com/automattic/harper/blob/c821f511f83c24401993e207f7e5cdb51ae872e6/LICENSE)，包含 Apache 许可声明及版权归属：

```text
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

   Copyright 2024 Automattic Inc.

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

## Rust 依赖

下表由 `cargo metadata --locked --format-version 1` 的版本和许可证字段，以及 `cargo tree --locked -e normal` 的依赖图生成。范围为 `deai-core`、`deai-ffi`、`deai-wasm` 的正常依赖并集：macOS 的 arm64/x86_64 目标与 `wasm32-unknown-unknown` 目标，保留默认 features，排除仅作为 dev/build 依赖的包。同一 crate 的不同版本分别列出，项目内三个 crate 不计入第三方表。

MPL-2.0 crates 均按上游源码原样使用，未作修改。各 crate 的完整许可证文本见其上游源码中的 `LICENSE`、`LICENSE-*` 或 `COPYING`；crates.io 包及上游源码入口可按表中名称和版本在 [crates.io](https://crates.io/) 查询。UniFFI 的完整 MPL-2.0 文本位于其[上游源码](https://github.com/mozilla/uniffi-rs/blob/v0.32.2/LICENSE)。

<!-- BEGIN GENERATED RUST DEPENDENCIES -->
| crate | 版本 | 许可证（Cargo 元数据原值） |
|---|---|---|
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 |
| ahash | 0.8.12 | MIT OR Apache-2.0 |
| aho-corasick | 1.1.5 | Unlicense OR MIT |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 |
| ammonia | 4.2.1 | MIT OR Apache-2.0 |
| anstream | 1.0.0 | MIT OR Apache-2.0 |
| anstyle | 1.0.14 | MIT OR Apache-2.0 |
| anstyle-parse | 1.0.0 | MIT OR Apache-2.0 |
| anstyle-query | 1.1.5 | MIT OR Apache-2.0 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 |
| askama | 0.16.1 | MIT OR Apache-2.0 |
| askama_derive | 0.16.1 | MIT OR Apache-2.0 |
| askama_macros | 0.16.1 | MIT OR Apache-2.0 |
| askama_parser | 0.16.1 | MIT OR Apache-2.0 |
| atomic_float | 1.1.0 | Apache-2.0 OR MIT OR Unlicense |
| basic-toml | 0.1.10 | MIT OR Apache-2.0 |
| bincode | 2.0.1 | MIT |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| blanket | 0.4.0 | MIT |
| boxcar | 0.2.14 | MIT |
| bumpalo | 3.20.3 | MIT OR Apache-2.0 |
| burn | 0.19.1 | MIT OR Apache-2.0 |
| burn-common | 0.19.1 | MIT OR Apache-2.0 |
| burn-core | 0.19.1 | MIT OR Apache-2.0 |
| burn-derive | 0.19.1 | MIT OR Apache-2.0 |
| burn-ir | 0.19.1 | MIT OR Apache-2.0 |
| burn-ndarray | 0.19.1 | MIT OR Apache-2.0 |
| burn-nn | 0.19.1 | MIT OR Apache-2.0 |
| burn-optim | 0.19.1 | MIT OR Apache-2.0 |
| burn-tensor | 0.19.1 | MIT OR Apache-2.0 |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT |
| bytemuck_derive | 1.12.1 | Zlib OR Apache-2.0 OR MIT |
| bytes | 1.12.1 | MIT |
| cached | 2.0.2 | MIT |
| cached_proc_macro | 2.0.0 | MIT |
| cached_proc_macro_types | 1.0.0 | MIT |
| camino | 1.2.6 | MIT OR Apache-2.0 |
| cargo-platform | 0.3.3 | MIT OR Apache-2.0 |
| cargo_metadata | 0.23.1 | MIT |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| clap | 4.6.7 | MIT OR Apache-2.0 |
| clap_builder | 4.6.7 | MIT OR Apache-2.0 |
| clap_derive | 4.6.7 | MIT OR Apache-2.0 |
| clap_lex | 1.1.1 | MIT OR Apache-2.0 |
| colorchoice | 1.0.5 | MIT OR Apache-2.0 |
| colored | 3.1.1 | MPL-2.0 |
| const-random | 0.1.18 | MIT OR Apache-2.0 |
| const-random-macro | 0.1.16 | MIT OR Apache-2.0 |
| convert_case | 0.10.0 | MIT |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 |
| crunchy | 0.2.4 | MIT |
| cssparser | 0.38.0 | MPL-2.0 |
| cubecl-common | 0.8.1 | MIT OR Apache-2.0 |
| cubecl-quant | 0.8.1 | MIT OR Apache-2.0 |
| darling | 0.20.11 | MIT |
| darling_core | 0.20.11 | MIT |
| darling_macro | 0.20.11 | MIT |
| data-encoding | 2.11.1 | MIT |
| derive-new | 0.7.0 | MIT |
| derive_more | 1.0.0 | MIT |
| derive_more | 2.1.1 | MIT |
| derive_more-impl | 1.0.0 | MIT |
| derive_more-impl | 2.1.1 | MIT |
| displaydoc | 0.2.7 | MIT OR Apache-2.0 |
| dtoa | 1.0.11 | MIT OR Apache-2.0 |
| dtoa-short | 0.3.5 | MPL-2.0 |
| either | 1.19.0 | MIT OR Apache-2.0 |
| embassy-futures | 0.1.2 | MIT OR Apache-2.0 |
| equivalent | 1.0.2 | Apache-2.0 OR MIT |
| errno | 0.3.14 | MIT OR Apache-2.0 |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| fid-rs | 0.2.0 | MIT OR Apache-2.0 |
| flate2 | 1.1.10 | MIT OR Apache-2.0 |
| float8 | 0.4.2 | MIT |
| fnv | 1.0.7 | Apache-2.0 / MIT |
| foldhash | 0.1.5 | Zlib |
| foldhash | 0.2.0 | Zlib |
| form_urlencoded | 1.2.2 | MIT OR Apache-2.0 |
| fs-err | 3.3.2 | MIT OR Apache-2.0 |
| fst | 0.4.7 | Unlicense/MIT |
| futures-core | 0.3.34 | MIT OR Apache-2.0 |
| futures-io | 0.3.34 | MIT OR Apache-2.0 |
| futures-lite | 2.6.1 | Apache-2.0 OR MIT |
| futures-task | 0.3.34 | MIT OR Apache-2.0 |
| futures-util | 0.3.34 | MIT OR Apache-2.0 |
| getopts | 0.2.24 | MIT OR Apache-2.0 |
| getrandom | 0.2.17 | MIT OR Apache-2.0 |
| getrandom | 0.3.4 | MIT OR Apache-2.0 |
| getrandom | 0.4.3 | MIT OR Apache-2.0 |
| glob | 0.3.4 | MIT OR Apache-2.0 |
| goblin | 0.8.2 | MIT |
| half | 2.7.1 | MIT OR Apache-2.0 |
| harper-brill | 2.11.0 | Apache-2.0 |
| harper-core | 2.11.0 | Apache-2.0 |
| harper-pos-utils | 2.11.0 | Apache-2.0 |
| harper-thesaurus | 2.11.0 | Apache-2.0 |
| hashbrown | 0.15.5 | MIT OR Apache-2.0 |
| hashbrown | 0.16.1 | MIT OR Apache-2.0 |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| heck | 0.5.0 | MIT OR Apache-2.0 |
| html5ever | 0.40.1 | MIT OR Apache-2.0 |
| icu_collections | 2.3.0 | Unicode-3.0 |
| icu_locale_core | 2.3.0 | Unicode-3.0 |
| icu_normalizer | 2.3.0 | Unicode-3.0 |
| icu_normalizer_data | 2.3.0 | Unicode-3.0 |
| icu_properties | 2.3.0 | Unicode-3.0 |
| icu_properties_data | 2.3.0 | Unicode-3.0 |
| icu_provider | 2.3.1 | Unicode-3.0 |
| ident_case | 1.0.1 | MIT/Apache-2.0 |
| idna | 1.1.0 | MIT OR Apache-2.0 |
| idna_adapter | 1.2.2 | Apache-2.0 OR MIT |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| is-macro | 0.3.8 | Apache-2.0 |
| is_terminal_polyfill | 1.70.2 | MIT OR Apache-2.0 |
| itertools | 0.15.0 | MIT OR Apache-2.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| js-sys | 0.3.106 | MIT OR Apache-2.0 |
| levenshtein_automata | 0.2.1 | MIT |
| libc | 0.2.190 | MIT OR Apache-2.0 |
| libm | 0.2.16 | MIT |
| litemap | 0.8.3 | Unicode-3.0 |
| lock_api | 0.4.14 | MIT OR Apache-2.0 |
| log | 0.4.34 | MIT OR Apache-2.0 |
| louds-rs | 0.7.0 | MIT OR Apache-2.0 |
| lru | 0.18.5 | MIT |
| maplit | 1.0.2 | MIT/Apache-2.0 |
| markup5ever | 0.40.0 | MIT OR Apache-2.0 |
| matrixmultiply | 0.3.11 | MIT/Apache-2.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| minimal-lexical | 0.2.1 | MIT/Apache-2.0 |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 |
| ndarray | 0.16.1 | MIT OR Apache-2.0 |
| new_debug_unreachable | 1.0.6 | MIT |
| nom | 7.1.3 | MIT |
| num-complex | 0.4.6 | MIT OR Apache-2.0 |
| num-integer | 0.1.47 | MIT OR Apache-2.0 |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| ordered-float | 5.5.0 | MIT |
| parking | 2.2.1 | Apache-2.0 OR MIT |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 |
| paste | 1.0.15 | MIT OR Apache-2.0 |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 |
| phf | 0.14.0 | MIT |
| phf_shared | 0.14.0 | MIT |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT |
| plain | 0.2.3 | MIT/Apache-2.0 |
| portable-atomic | 1.15.0 | Apache-2.0 OR MIT |
| potential_utf | 0.1.6 | Unicode-3.0 |
| ppv-lite86 | 0.2.21 | MIT OR Apache-2.0 |
| precomputed-hash | 0.1.1 | MIT |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| pulldown-cmark | 0.13.4 | MIT |
| pulldown-cmark-escape | 0.11.0 | MIT |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| rand | 0.9.5 | MIT OR Apache-2.0 |
| rand_chacha | 0.9.0 | MIT OR Apache-2.0 |
| rand_core | 0.9.5 | MIT OR Apache-2.0 |
| rand_distr | 0.5.1 | MIT OR Apache-2.0 |
| rawpointer | 0.2.1 | MIT/Apache-2.0 |
| rayon | 1.12.0 | MIT OR Apache-2.0 |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 |
| regex | 1.13.1 | MIT OR Apache-2.0 |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 |
| rmp | 0.8.15 | MIT |
| rmp-serde | 1.3.1 | MIT |
| rs-conllu | 0.3.0 | MIT OR Apache-2.0 |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT |
| rustix | 1.1.5 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| ruzstd | 0.9.0 | MIT |
| same-file | 1.0.6 | Unlicense/MIT |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 |
| scroll | 0.12.0 | MIT |
| scroll_derive | 0.12.1 | MIT |
| semver | 1.0.28 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde-wasm-bindgen | 0.6.5 | MIT |
| serde_bytes | 0.11.19 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.151 | MIT OR Apache-2.0 |
| serde_spanned | 1.1.1 | MIT OR Apache-2.0 |
| simd-adler32 | 0.3.10 | MIT |
| siphasher | 1.0.4 | MIT OR Apache-2.0 |
| slab | 0.4.12 | MIT |
| smallvec | 1.16.2 | MIT OR Apache-2.0 |
| smawk | 0.3.3 | MIT |
| spin | 0.10.1 | MIT |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 |
| string_cache | 0.11.0 | MIT OR Apache-2.0 |
| strsim | 0.11.1 | MIT |
| strum | 0.28.0 | MIT |
| strum_macros | 0.28.0 | MIT |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.6 | MIT OR Apache-2.0 |
| synstructure | 0.14.0 | MIT |
| tempfile | 3.27.0 | MIT OR Apache-2.0 |
| tendril | 0.5.1 | MIT OR Apache-2.0 |
| textwrap | 0.16.4 | MIT |
| thiserror | 1.0.69 | MIT OR Apache-2.0 |
| thiserror | 2.0.21 | MIT OR Apache-2.0 |
| thiserror-impl | 1.0.69 | MIT OR Apache-2.0 |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 |
| tiny-keccak | 2.0.2 | CC0-1.0 |
| tinystr | 0.8.4 | Unicode-3.0 |
| toml | 1.1.6+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_datetime | 1.1.1+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_parser | 1.1.3+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_writer | 1.1.2+spec-1.1.0 | MIT OR Apache-2.0 |
| trie-rs | 0.4.2 | MIT OR Apache-2.0 |
| twox-hash | 2.1.5 | MIT |
| typed-path | 0.12.3 | MIT OR Apache-2.0 |
| unicase | 2.10.0 | MIT OR Apache-2.0 |
| unicode-blocks | 0.1.10 | MIT |
| unicode-ident | 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-script | 0.5.8 | MIT OR Apache-2.0 |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 |
| unicode-width | 0.2.2 | MIT OR Apache-2.0 |
| unicode-xid | 0.2.6 | MIT OR Apache-2.0 |
| uniffi | 0.32.2 | MPL-2.0 |
| uniffi_bindgen | 0.32.2 | MPL-2.0 |
| uniffi_core | 0.32.2 | MPL-2.0 |
| uniffi_internal_macros | 0.32.2 | MPL-2.0 |
| uniffi_macros | 0.32.2 | MPL-2.0 |
| uniffi_meta | 0.32.2 | MPL-2.0 |
| uniffi_pipeline | 0.32.2 | MPL-2.0 |
| uniffi_udl | 0.32.2 | MPL-2.0 |
| unty | 0.0.4 | MIT OR Apache-2.0 |
| url | 2.5.8 | MIT OR Apache-2.0 |
| utf8_iter | 1.0.4 | Apache-2.0 OR MIT |
| utf8parse | 0.2.2 | Apache-2.0 OR MIT |
| uuid | 1.27.0 | Apache-2.0 OR MIT |
| walkdir | 2.5.0 | Unlicense/MIT |
| wasm-bindgen | 0.2.129 | MIT OR Apache-2.0 |
| wasm-bindgen-futures | 0.4.79 | MIT OR Apache-2.0 |
| wasm-bindgen-macro | 0.2.129 | MIT OR Apache-2.0 |
| wasm-bindgen-macro-support | 0.2.129 | MIT OR Apache-2.0 |
| wasm-bindgen-shared | 0.2.129 | MIT OR Apache-2.0 |
| web-time | 1.1.0 | MIT OR Apache-2.0 |
| web_atoms | 0.3.0 | MIT OR Apache-2.0 |
| weedle2 | 5.0.0 | MIT |
| winnow | 1.0.4 | MIT |
| writeable | 0.6.4 | Unicode-3.0 |
| yoke | 0.8.3 | Unicode-3.0 |
| yoke-derive | 0.8.4 | Unicode-3.0 |
| zerocopy | 0.8.61 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zerocopy-derive | 0.8.61 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zerofrom | 0.1.8 | Unicode-3.0 |
| zerofrom-derive | 0.1.8 | Unicode-3.0 |
| zerotrie | 0.2.5 | Unicode-3.0 |
| zerovec | 0.11.8 | Unicode-3.0 |
| zerovec-derive | 0.11.6 | Unicode-3.0 |
| zip | 8.6.0 | MIT |
| zlib-rs | 0.6.8 | Zlib |
| zmij | 1.0.23 | MIT |
| zopfli | 0.8.3 | Apache-2.0 |
<!-- END GENERATED RUST DEPENDENCIES -->

### 重新生成依赖表

在 `core/` 中运行 `source ~/.cargo/env`，再运行以下 Python 脚本。用输出替换上方 `BEGIN/END GENERATED RUST DEPENDENCIES` 标记之间的表格。

```python
import json
import re
import subprocess


def cargo(*args):
    return subprocess.check_output(["cargo", *args], text=True)


metadata = json.loads(cargo("metadata", "--locked", "--format-version", "1"))
selections = [
    ("aarch64-apple-darwin", "deai-core", "deai-ffi"),
    ("x86_64-apple-darwin", "deai-core", "deai-ffi"),
    ("wasm32-unknown-unknown", "deai-core", "deai-wasm"),
]
selected = set()
for target, *roots in selections:
    args = ["tree", "--locked", "-e", "normal", "--target", target,
            "--prefix", "none", "--format", "{p}"]
    for root in roots:
        args.extend(["-p", root])
    for line in cargo(*args).splitlines():
        match = re.match(r"^(\S+) v(\S+)", line)
        if match:
            selected.add(match.groups())
packages = sorted(
    (p for p in metadata["packages"]
     if (p["name"], p["version"]) in selected and p["source"] is not None),
    key=lambda p: (p["name"], p["version"]),
)
assert all(p["license"] for p in packages), "依赖缺少许可证字段"
print("| crate | 版本 | 许可证（Cargo 元数据原值） |")
print("|---|---|---|")
for p in packages:
    print(f"| {p['name']} | {p['version']} | {p['license']} |")
```

## Swift 与视觉资源

应用未捆绑第三方 Swift packages、图片、图标或字体。应用图标为原创；界面使用系统提供的字体和 SF Symbols。

## 演示中的应用图形

演示视频与 GIF 中标注 Word、文本编辑和备忘录的三个图形为本项目手工编写的通用 SVG，采用仓库 MIT 许可证；它们替代了早期演示中提取的应用图标，不是官方品牌标志。可编辑源文件与说明见 [docs/demo/icons](docs/demo/icons/README.md)。应用名称用于标明兼容对象，相关名称归各自权利人所有。

## Windows client

`Interop.UIAutomationClient` 10.19041.0 ([UIAutomation-Interop](https://github.com/Roemer/UIAutomation-Interop)) uses the following MIT license:

```text
MIT License

Copyright (c) 2019 Roman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The self-contained Windows client includes Microsoft .NET 8 runtime and `System.Security.Cryptography.ProtectedData` under the .NET MIT license; runtime third-party notices are shipped by the publish output. See https://github.com/dotnet/runtime/blob/v8.0.31/LICENSE.TXT and https://github.com/dotnet/runtime/blob/v8.0.31/THIRD-PARTY-NOTICES.TXT.

The Windows x64 native bridge statically links the Microsoft Visual C++ runtime; its redistribution is subject to the Visual Studio Build Tools license. See https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170.
