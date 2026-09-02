# Kistulentz English Language Pack

Kistulentz’s optional English language pack runs entirely on the user’s Mac. It contains a Python runtime, the `benepar_en3` model, Benepar, PyTorch, spaCy tokenization, and their runtime dependencies. The base Kistulentz application does not contain or silently download this pack.

Benepar (Berkeley Neural Parser) is by Nikita Kitaev and contributors and is distributed under the Apache License 2.0. Its official source is <https://github.com/nikitakit/self-attentive-parser>.

The `benepar_en3` model is downloaded from Benepar's official GitHub model release and pinned by SHA-256 in the pack builder. The relocatable CPython runtime comes from Astral's `python-build-standalone` project; its archive URL and SHA-256 are pinned separately for Apple silicon and Intel. CPython and its bundled components retain their upstream license files inside the runtime.

The language-pack archive must retain the license and package-metadata files shipped by every included dependency. Those files remain inside the Python runtime’s `site-packages` directory. The pack builder must also retain any license or notice files distributed with the `benepar_en3` model.

Kistulentz uses Benepar output as evidence for advisory sentence-structure signals. A parse is not proof of a writing error. The app does not automatically replace prose based on a parse.

The language pack never opens a network connection while analyzing text. Installation is a separate, explicitly confirmed download from a Kistulentz GitHub release. If the pack is absent, invalid, busy, or unavailable, Kistulentz continues with its native local analysis.
