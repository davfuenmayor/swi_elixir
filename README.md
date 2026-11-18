# swi_elixir

[![Native SWI builds](https://github.com/davfuenmayor/swi_elixir/actions/workflows/native.yml/badge.svg?branch=main)](https://github.com/davfuenmayor/swi_elixir/actions/workflows/native.yml?query=branch%3Amain)

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
limits each pull (default 5,000). Timeouts do not roll back side effects.

Port isolates crashes and can kill a worker that misses its deadline. Reload
Prolog state after a reset. NIF sessions share ordinary predicates and modules
inside the BEAM. Native cleanup can block on a Prolog cleanup handler.

| Prolog | Elixir |
| --- | --- |
| Atom | `{:atom, name}` |
| Number, string, proper list | Number, string, list |
| Compound | `{:compound, name, args}` |
| Unbound variable | `{:var, id}` |
| Improper list | `{:cons, head, tail}` |
| Other terms, including cycles | `{:prolog, text}` |

## Livebooks

Open [the index](livebooks/intro.livemd) from the checkout. Lessons cover queries,
search, the backends, theorem proving, Metagol and Aleph.

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md).
