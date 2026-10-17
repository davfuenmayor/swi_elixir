# License scope and third-party notices

The [MIT license](LICENSE) covers original swi_elixir code and documentation,
including the Elixir wrapper, C NIF shim, shared Prolog bridge, build scripts,
tests, and original teaching material. Its warranty disclaimer and limitation
of liability apply to that material.

Third-party software and borrowed portions of examples and notebooks retain
their upstream terms. The MIT license does not replace those terms or grant
additional rights to that material.

| Material | Terms and notices |
| --- | --- |
| Bundled SWI-Prolog 10.0.1 runtime | [BSD-2-Clause and component-specific notices](native/licenses/). Archives include the runtime, its Prolog libraries, LibBF (MIT), Mersenne Twister (modified BSD), zlib 1.3.2 (zlib license), and the wrapper NIF built with OTP 27 headers (Apache-2.0). GCC runtime exception and MinGW-w64 notices accompany relevant toolchain components. GMP and readline are excluded. Copyright notices, license conditions, and disclaimers accompany the archive and extracted runtime. See [build notes](MULTIPLATFORM.md). |
| `vendor/leanHaT/` and `vendor/nanoCoP-i-HT/` | GNU GPL; upstream notices do not specify a version. Preserve the copyright notices, upstream ReadMe files, and [GPL text](vendor/COPYING). See [vendor notes](vendor/README.md). |
| `vendor/metagol/` | [BSD-3-Clause](vendor/metagol/LICENSE), copyright (c) 2016, Metagol authors. Preserve its copyright notice, license conditions, and disclaimer. |
| Borrowed Metagol example portions in `examples/metagol_ilp.pl`, `examples/metagol_tasks.pl`, and `livebooks/05_metagol.livemd` | The same Metagol BSD-3-Clause terms. Their origins and local adaptations are recorded in [ILP provenance](docs/ilp-provenance.md). |
| `vendor/aleph/aleph.pl` | The source states that Aleph is freely available for academic purposes and asks users intending commercial use to contact Ashwin Srinivasan first. Preserve the [original source notice](vendor/aleph/aleph.pl). No MIT or other open-source license is inferred for Aleph. |
| Borrowed Aleph task/example portions in `examples/aleph_trains.pl`, `examples/aleph_membership.pl`, and `livebooks/06_aleph.livemd` | These portions are excluded from the wrapper's MIT grant. Preserve their upstream notices and attributions; see [ILP provenance](docs/ilp-provenance.md). The wrapper's license does not resolve permissions for those portions. |

The source repository includes these third-party systems and teaching examples.
The Hex package includes the core wrapper, bundled native runtime and its
notices, build sources, README, MIT license, and this notice; `vendor/`, `examples/`, and `livebooks/` are
excluded. This separates the core library distribution from the demonstration
systems. Distributing or combining those systems requires complying with their
applicable terms; separate directories do not waive those requirements.

Additional formula and dataset attributions are recorded in
[prover showcases](docs/prover-showcases.md) and
[ILP provenance](docs/ilp-provenance.md). Attribution does not relicense
third-party material.
