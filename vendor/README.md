These original archives were downloaded from Jens Otten's upstream website:

| Distribution | URL | SHA-256 of archive |
| --- | --- | --- |
| leanHaT 1.0 (2025) | https://leancop.de/leanhat/programs/leanHaT.tar.gz | c980d8dae5adce37614ef0eb7f27b54c7006fba039e98bd4c75658b7b61b6c39 |
| nanoCoP-i-HT 2.0ihat (2025 distribution; SWI core dated 2021) | https://www.leancop.de/ihat/programs/nanoCoP-i-HT.tar.gz | 6dcbab09f9ed12d49c000f06947d7106409b24bb2940c9caee97f16495a61804 |

The original archive files are preserved unchanged. Copyright belongs to Jens
Otten. The sources state GNU General Public License without specifying a
version. Original copyright,
license notices and ReadMe files are preserved. A GPL text is included in
COPYING; see its section 14 for programs without a specified license version.
These files keep their upstream licensing independently of the wrapper.

The small example adapters in `../examples/` load the SWI variants into separate
modules so their `prove` predicates and operators do not collide. The nanoCoP
adapter makes `lit/4` and `pathlim/0` thread-local: upstream uses these as mutable
search scratch space. This gives each query engine its own clauses. It also
restores `=` precedence before reconsulting the core (the translator changes
it), and calls the upstream equality and HT-axiom transformations. The leanHaT
adapter also calls its upstream equality transformation. nanoCoP's load-time
`occurs_check` change is saved and restored; its required flag is scoped to each
proof invocation and restored on success, failure, exceptions, or early halt. There are no
changes to the proof algorithms. The upstream singleton warning is harmless.

`leanhat:prove_text/1` runs HT. `nanocop:prove_text/2` accepts `intu` or `ht`;
`nanocop:prove_text/3` also returns the upstream connection proof unchanged.
Tutorial and paper formula attributions are in
[the showcase provenance ledger](../docs/prover-showcases.md).
These examples accept upstream formula syntax as a Prolog string, parsed by
SWI in the prover module. The adapters load source files relative to themselves.
They are development examples, excluded from the Hex library package along
with the vendored systems. The package includes the wrapper's Elixir and C
sources, Prolog bridge, Makefile, and license notices. See
[license scope and third-party notices](../THIRD_PARTY_NOTICES.md).

## Inductive Logic Programming systems

`metagol/` contains unchanged source and notices from **Andrew Cropper and
Stephen H. Muggleton's Metagol**, BSD-3-Clause. `aleph/` contains the unchanged
module version of **Ashwin Srinivasan's Aleph**, ported by **Fabrizio Riguzzi and
Paolo Niccolò Giubelli**. Aleph's source carries an academic-use notice and a
request to contact Srinivasan for commercial use; no BSD/GPL license is inferred.

The [ILP provenance ledger](../docs/ilp-provenance.md) records pinned repository
commits, source hashes, licenses, upstream example links and all adaptations.
These learners run through project-authored examples; their algorithms are
not changed. Their vendor notices remain separate from the wrapper's licensing.
