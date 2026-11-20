# swi_elixir

[![Native SWI builds](https://github.com/davfuenmayor/swi_elixir/actions/workflows/native.yml/badge.svg?branch=main)](https://github.com/davfuenmayor/swi_elixir/actions/workflows/native.yml?query=branch%3Amain)
[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fdavfuenmayor%2Fswi_elixir%2Fblob%2Fmain%2Flivebooks%2Fintro.livemd)

Run SWI-Prolog from Elixir through a Port or a NIF. Both use the same API.

```elixir
{:ok, swi} = SWI.start_link(backend: :port)
SWI.query(swi, "member(X, [a,b])") |> Enum.to_list()
# [%{"X" => {:atom, "a"}}, %{"X" => {:atom, "b"}}]
SWI.call(swi, "2 + 2 =:= 4") # {:ok, true}
SWI.stop(swi)
```

## Platforms and native bundles

Use 64-bit Elixir 1.18+ and OTP 27+. For a published release, Mix downloads and
verifies SWI and its matching NIF. You need no compiler or system SWI install.

Targets are Linux glibc x86-64 and ARM64, Windows x86-64, and macOS Intel and
Apple Silicon. See [builds, local bundles and releases](MULTIPLATFORM.md).

## Sessions

`SWI.load/3` consults a file. Pass one UTF-8 goal to `SWI.query/3` for a lazy stream
of bindings or `SWI.call/3` for a Boolean. Query errors raise `SWI.Error` during
enumeration. `call/3` returns `{:ok, boolean}` or `{:error, reason}`.

A session supports one active query. Exhaustion or `Enum.take/2` closes it. Use
separate sessions for parallel searches. `timeout:` is in milliseconds and
sets Prolog's deadline for each pull (default 5,000). A Prolog `:timeout`
leaves the session alive. Timeouts do not roll back side effects.

To swap backends, start a new session with `backend: :port` or `backend: :nif`
and reload your program. The same calls, goals, and result shapes work with both.

- **Port** gives each session its own SWI process. `:port_timeout` means Elixir
  killed the process after waiting `timeout + cleanup_timeout` on a query or
  load. The grace period defaults to 1,000 ms. Use `swipl:` or `SWIPL` to
  override the executable.
- **NIF** embeds SWI in the BEAM. Sessions share ordinary predicates and modules.
  A timed-out goal returns once cleanup finishes. A stuck native call or
  cleanup can retain an engine and keep using CPU. Use Port when you need
  to reclaim those resources at a deadline.

If the wrapper loses or discards a process or engine, the next query or load
reports `:session_reset` once before a later request reconnects. Reload your
files after Port loss. Shared Prolog state can survive a NIF engine reset.

Use `halt/1` only with Port. In a NIF session it can terminate the BEAM.

| Prolog | Elixir |
| --- | --- |
| Atom | `{:atom, name}` |
| Number, string, proper list | Number, string, list |
| Compound | `{:compound, name, args}` |
| Unbound variable | `{:var, id}` |
| Improper list | `{:cons, head, tail}` |
| Other terms, including cycles | `{:prolog, text}` |

## Livebooks

Open [the index](livebooks/intro.livemd) or use the badge above. Lessons cover
queries, search, the backends, theorem proving, Metagol and Aleph.

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
