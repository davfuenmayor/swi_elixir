# Inductive Logic Programming Livebooks: provenance and reproduction

Sources obtained and read on **2026-10-13**. The two teaching notebooks are
[Metagol](../livebooks/05_metagol.livemd) and [Aleph](../livebooks/06_aleph.livemd).
The prose, diagrams, Elixir session orchestration, evaluation helpers,
diagnostic cases and regression tests were authored for this project.
The learning algorithms are the upstream Prolog implementations, not
implementations written for these notebooks.

## Metagol

Repository: [metagol/metagol](https://github.com/metagol/metagol), pinned commit
[`7b617992d30d3cee37a6f4bb8667f717a46cc6a3`](https://github.com/metagol/metagol/tree/7b617992d30d3cee37a6f4bb8667f717a46cc6a3).
The repository's preferred system citation is **Andrew Cropper and Stephen H.
Muggleton, Metagol System (2016)**. Its AUTHORS file additionally credits
Martin Möhrmann, University of Oxford and Imperial College London; the file is
preserved alongside `metagol.bib`. This is the archived Metagol implementation
requested for the lesson, not Popper or a new fork.

**License: BSD-3-Clause**, copyright (c) 2016, Metagol authors. The upstream
core, LICENSE, AUTHORS, README and bibliography are copied unchanged into
`vendor/metagol/`. Adapted example code retains attribution and uses that
upstream license for the borrowed portions.

| File | SHA-256 of unchanged upstream file |
| --- | --- |
| `metagol.pl` | `f63da460581e7926c85c6e08267e1426b3190e374dae1325f7f7c2a1b6435e65` |
| `LICENSE` | `c8590582fcf52bc28196ae664669fc9c630e467d1e050f6ec21de2596baa9b0e` |

Formula/data origins in `examples/metagol_tasks.pl` and the inline source in
`livebooks/05_metagol.livemd`:

| Lesson | Exact upstream source | Changes made here |
| --- | --- | --- |
| Grandparent / predicate invention | [README grandparent example](https://github.com/metagol/metagol/blob/7b617992d30d3cee37a6f4bb8667f717a46cc6a3/README.md) | Retain original family facts, five positive examples and one negative; prefix primitives `mg_`; add Nora–Ivy–Leo background and three diagnostic queries; use the shared four-template bias below. |
| Recursive ancestry | [examples/kinship2.pl](https://github.com/metagol/metagol/blob/7b617992d30d3cee37a6f4bb8667f717a46cc6a3/examples/kinship2.pl) | Retain family graph and three positive examples; prefix `parent`; add four diagnostic queries; cap at two clauses. |
| Nested droplasts | [examples/droplasts.pl](https://github.com/metagol/metagol/blob/7b617992d30d3cee37a6f4bb8667f717a46cc6a3/examples/droplasts.pl) | Same transformation task and interpreted map; replace random generation with two fixed positive examples, add one negative and four diagnostics, restrict primitives to tail and reverse, and cap at three clauses. No droplast implementation is supplied. |

Original example hashes at that revision:

- `examples/kinship2.pl`: `5ec8bc33052a9797bf593350a7268dc3da3aadad11c572e2184be072a1a74247`
- `examples/droplasts.pl`: `b0d13bcfe413d387b8799bea7915a90add85d02a9c8cd2a9a617edfda780fb8a`

The shared bias consists of upstream identity, chain, tail-recursive and
higher-order metarule forms, with explicit names. It differs from the precise
selection in each upstream example. We omit the droplasts example's distractor
primitives, random generator, filter IBK and functional-test flag. Its source
credits **A. Cropper and S.H. Muggleton, “Learning Higher-Order Logic Programs
through Abstraction and Invention,” IJCAI 2016**, and **R. Morel, A. Cropper and
L. Ong, “Typed Meta-Interpretive Learning of Logic Programs,” JELIA 2019**.
Those attributions describe the example's lineage; these notebooks do not
reproduce either paper's experiments or claim their benchmark results.

`metagol:learn/3` performs the learning. The adapter uses the pinned upstream
private `metasub_to_clause/2` converter, also used by its `pprint/1`, to obtain
ordinary Prolog clauses. The interpreter for map has an ordinary runtime
counterpart in the adapter solely to execute the returned program. No expected
hypothesis is asserted in place of a learned hypothesis.

## Aleph

Repository: [friguzzi/aleph](https://github.com/friguzzi/aleph), pinned commit
[`cc6ef273dc270a8a26a078ad6e90db1ba1fe31ef`](https://github.com/friguzzi/aleph/tree/cc6ef273dc270a8a26a078ad6e90db1ba1fe31ef).
**Ashwin Srinivasan** developed Aleph. **Fabrizio Riguzzi** ported it to SWI;
**Paolo Niccolò Giubelli and Fabrizio Riguzzi** developed the module version used
here. The core identifies itself as Aleph 5, last modified 2007-03-11; the
pinned commit identifies this particular SWI distribution.

The unchanged core and repository README are in `vendor/aleph/`. The core's
original header says it is freely available for academic purposes and asks
those intending commercial use to contact Ashwin Srinivasan. We preserve that
notice and **do not infer a BSD, GPL or other open-source license** for Aleph.
This is separate from Metagol's licensing and the wrapper's own status.

| File | SHA-256 of unchanged upstream file |
| --- | --- |
| `prolog/aleph.pl` → `vendor/aleph/aleph.pl` | `621d35d219e150aacee502bc0e469cd0e0e139292fb476153dcda5367bbc3bd5` |

| Lesson | Exact upstream source | Changes made here |
| --- | --- | --- |
| Michalski's trains | [prolog/examples/train.pl](https://github.com/friguzzi/aleph/blob/cc6ef273dc270a8a26a078ad6e90db1ba1fe31ef/prolog/examples/train.pl) | Copy into `examples/aleph_trains.pl`, add attribution/module declaration, replace the library import with the relative vendored path, add four project-authored holdout structures before `end_bg`. Original training labels, modes, determinations and background facts remain. |
| Recursive membership | [prolog/examples/recursion.pl](https://github.com/friguzzi/aleph/blob/cc6ef273dc270a8a26a078ad6e90db1ba1fe31ef/prolog/examples/recursion.pl) | Copy into `examples/aleph_membership.pl`, add attribution/module declaration and change the library import. Retain all 19 positive and six negative examples and the original modes/determinations. Four diagnostic queries are in the adapter. |

Original example hashes at that revision:

- `prolog/examples/train.pl`: `ba7c47c9682a6a7d73e5d4205c523379310ee30030e90f389c9d121030b73d05`
- `prolog/examples/recursion.pl`: `c96d5c9e5e3c9e9b8447b98a27fe5f3ff504aa65ee4b12043bb2496b934d5474`

The name **Michalski's trains** follows the upstream example's attribution.
We obtained the dataset from this repository, not from an independently
consulted original Michalski publication. The repository says its examples
were downloaded from Srinivasan's Oxford Aleph collection and ported to SWI.

The [SWI Aleph manual](https://friguzzi.github.io/aleph/doc/manual.html) and the
[pinned README](https://github.com/friguzzi/aleph/blob/cc6ef273dc270a8a26a078ad6e90db1ba1fe31ef/README.md)
supply the induction workflow, mode notation and output-argument APIs.
The adapter calls public `sat/1`, `bottom/1`, `reduce/1` and `induce/1`.
It sets zero training noise, a 5,000-node search bound, and the experiment's
clause-length limit. The notebook compares four literals (the shared-witness
rule is expressible) with three (this run memorizes five facts). These are
project-designed bias experiments, not upstream benchmark measurements.

## What is checked, and what is not

Training examples alone are passed to learning. Project-authored test labels
are used only afterward. Holdout background facts may remain visible, as is
normal in relational learning; **no claim of an independent statistical test
set or inductive-distribution accuracy is made**. The toy diagnostics are
chosen to expose predicate composition, recursion, empty-list domains and
shared-variable meaning. They are not automatically generated from the
returned hypothesis.

The learned clauses are executed by SWI on every labelled case. Metagol
clauses are temporarily asserted with reference-based cleanup. Aleph installs
its clauses while learning; the adapter queries them, then removes its task's
target clauses and initialization command shims. Aleph data is re-read for
each experiment. Metagol's changed options and primitive declarations are
saved/restored; interpreted map is installed once to avoid reconsult growth.
Both demonstrations serialize their own calls. Upstream mutable registries
and native modules are shared, so arbitrary concurrent calls to these same
learner modules outside the adapters are not isolated.

The Elixir helper uses the same session/load/query/stop API for both backends.
It records upstream source location and inference totals, captures search
trace, and always closes the session. Counts/times include orchestration and
evaluation; Aleph counts also include reading the task, saturation and
reduction. They are not a solver-only benchmark. The per-query budget is
15 seconds; timeout means unknown, never a successful model or an impossibility
result. A bounded search may return no hypothesis, a fallback/memorizing theory,
or a theory that fails the diagnostic cases.

Regression tests compare actual predictions, check the known restricted-bias
failures, inject faults into both upstream learning entry points, and verify
repeat/timeout cleanup. `elixir scripts/check_livebooks.exs` evaluates all
notebooks twice in one VM. This is standalone cell validation; interactive
Livebook UI rendering and reruns remain a separate check.
