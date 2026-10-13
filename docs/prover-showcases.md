# Prover showcase provenance

Sources consulted on **2026-10-13**. This ledger applies to
`examples/showcase.exs`, `examples/prover_showcase.pl`, and Livebooks 02 and 04.
The Elixir generators, diagnostic helper, adapter changes, tests and notebook
prose were written for this project. They are not upstream prover code.

## Provers and licensing

**Jens Otten** is the author of [leanHaT](https://leancop.de/leanhat/) and
[nanoCoP-i-HT](https://www.leancop.de/ihat/). We use leanHaT 1.0
(core dated 2025-04-01) and nanoCoP-i-HT 2.0ihat (2025 distribution, nanoCoP-i
SWI core 2.0 dated 2021-05-01). Their unchanged files, copyright and GPL notices
are in `vendor/`. [The vendor ledger](../vendor/README.md) records exact archive
URLs and SHA-256 digests. Upstream licensing remains applicable to those files;
the tutorial and paper attributions below do not relicense the provers.

The adapters parse upstream formula syntax and apply upstream equality
preprocessing; nanoCoP also applies its upstream HT embedding and scopes its
occurs-check flag and scratch clauses. Its optional `prove_text/3` returns the
original upstream connection proof. No proof-search algorithm was rewritten.
leanHaT's `prove/2` second argument is an iterative-deepening bound, despite an
upstream comment mentioning `Proof`; it does not supply a proof object.

## Formula sources and changes

| Showcase | Source and attribution | Project adaptation |
| --- | --- | --- |
| Function chain 4 | Jens Otten, [TABLEAUX 2019 tutorial, ex_f12.pl](https://jens-otten.de/tutorial_tableaux19/examples/ex_f12.pl) | Generated smaller instance of the same family; 4 nested function applications instead of 12. |
| Function chain 20 | Otten, [ex_f20.pl](https://jens-otten.de/tutorial_tableaux19/examples/ex_f20.pl) | Generated the published 20-step formula in prover syntax. |
| Four pigeons, three holes | Otten, [ex_pigeon3.pl](https://jens-otten.de/tutorial_tableaux19/examples/ex_pigeon3.pl) | Generated the same 4-by-3 placement/collision formula; collision order is immaterial. |
| Pelletier 16 | Jens Otten and Torsten Schaub, [HT paper, Example 1](https://arxiv.org/html/2601.03848v1) | `(p=>q);(q=>p)`; mathematical formula transcribed into prover syntax. |
| Pelletier 18 | Otten and Schaub, same Example 1 | `ex Y:all X:(p(Y)=>p(X))`; variables renamed. |
| Excluded middle | Otten and Schaub, §1 | `p; ~p`; negative control in both modes. |
| Double-negation elimination | Standard logical law, selected here as an additional negative control | `(~ ~p)=>p`; project-selected example, not attributed as a tutorial problem. |

Tutorial: **Jens Otten, “How to Build an Automated Theorem Prover,” invited
TABLEAUX 2019 tutorial**, London, 2 September 2019,
[overview and original downloads](https://jens-otten.de/tutorial_tableaux19/).
The tutorial presents classical provers. We selected problems with constructive
proofs; classical validity alone would not justify an HT/intuitionistic result.
We did not copy its Prolog programs or example files into this project. Our
Elixir generators produce formulas and translate TPTP `&`, `|`, `![X]` into
upstream prover conjunction `,`, disjunction `;`, and `all X:`. Function symbols,
atoms, implications and quantifier scopes retain their logical meaning.

Paper: **Jens Otten and Torsten Schaub, “Implementing the First-Order Logic of
Here and There,”** ICLP 2025, EPTCS 439 (2026), pp. 453–468,
[DOI 10.4204/EPTCS.439.31](https://doi.org/10.4204/EPTCS.439.31),
[arXiv:2601.03848v1](https://arxiv.org/html/2601.03848v1), **CC BY 4.0**.
The two Pelletier problem numbers follow this paper; we did not consult
Pelletier's original benchmark publication. Changes are limited to notation and
variable names. Our explanatory prose is a paraphrase, not a quotation.

## Why those expected results?

The chain follows by repeated universal instantiation and modus ponens.
The finite pigeonhole implication follows constructively by case analysis of
placements: some pair shares a hole. Both therefore hold intuitionistically
and in HT. Example 1 of Otten and Schaub supplies the contrasting validity of
Pelletier 16 and 18. Excluded middle and double-negation elimination each fail
at the here world when `p` holds only there. Such a two-world countermodel
also refutes intuitionistic validity.

These mathematical expectations are separate from observed solver outcomes.
Tests require actual proof-search calls and the expected success/exhaustion
on the selected finite runs. No timeout is an invalidity verdict. nanoCoP's HT
embedding is sound but incomplete; general first-order search need not
terminate. The 20-step chain is intentionally shown in nanoCoP intuitionistic
mode; the four-pigeon problem runs in both nanoCoP modes. We do not assert that
all provers finish those workloads within the same budget.

## Execution evidence and its limits

SWI's [library(prolog_wrap)](https://www.swi-prolog.org/pldoc/man?section=prologwrap)
provides temporary predicate instrumentation. The diagnostic wraps leanHaT's
recursive `prove/4` and nanoCoP's recursive `prove/10`, increments an engine-local
counter, and always calls the original predicate. `setup_call_cleanup/3`
removes the wrapper on success, failure, exceptions, timeout and early halt.
The Livebook also obtains the original clause's source file/line from SWI and
prints that file's SHA-256. Predicate wrappers are shared within a runtime, so
these diagnostics must run serially with respect to other prover sessions.

Counts demonstrate execution, not logical soundness or independent certificate
verification. Inference totals include preprocessing and instrumentation;
notebook 04 measures adapter calls without instrumentation. nanoCoP's raw
proof is its connection data, not a rendered derivation. HT proof terms refer
to its intuitionistic translation. leanHaT has no proof output in this adapter.
