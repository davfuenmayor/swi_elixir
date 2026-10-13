# swi_elixir

A small Elixir bridge to SWI-Prolog, with a persistent **Port** backend and an
embedded **NIF** backend. Elixir owns sessions and consumes lazy solution
streams; SWI handles parsing, unification, backtracking and proof search.
There are no Hex dependencies, typespecs, or alternate logic syntax.

Original wrapper code and documentation are licensed under [MIT](LICENSE),
including its warranty disclaimer and limitation of liability. Third-party
systems and borrowed example portions retain their upstream terms; see
[license scope and third-party notices](THIRD_PARTY_NOTICES.md). The Hex package
contains the core wrapper and build sources, excluding vendors and teaching
examples.

```elixir
{:ok, prolog} = SWI.start_link(backend: :port) # or :nif
SWI.query(prolog, "member(X, [a,b,c])") |> Enum.to_list()
# [%{"X" => {:atom, "a"}}, %{"X" => {:atom, "b"}}, %{"X" => {:atom, "c"}}]
SWI.call(prolog, "1 + 1 =:= 2") # {:ok, true}
SWI.call(prolog, "fail")        # {:ok, false}
SWI.stop(prolog)
```

## Build on Linux

Tested locally with **SWI-Prolog 10.0.1**, **Elixir 1.20.4**, **OTP 29.1.1**
(ERTS 17.1), x86-64 Linux. The existing checkout is 10.1 development, so the
installer builds its stable `V10.0.1` tag in a temporary worktree without
changing the checkout's branch or files.

Prerequisites: Elixir >= 1.18, OTP >= 27 (built-in `:json`), a C compiler, make,
pkg-config, SWI with multithreading, development headers and shared `libswipl`,
and the `http/json`, `time`, `readutil`, and (for Port) `unix` libraries. For the pinned source build:

```sh
apt-get update
apt-get install -y build-essential cmake ninja-build pkg-config libgmp-dev \
  libssl-dev zlib1g-dev libossp-uuid-dev
# Run inside swi_elixir, using the already cloned SWI repo:
scripts/install-swi.sh ../swipl-devel
mix compile
mix test
```

If cloning elsewhere, use `git clone --branch V10.0.1
https://github.com/SWI-Prolog/swipl-devel.git` and pass that checkout to the
installer. Installation defaults to `/usr/local`; set `SWI_PREFIX` for another
prefix and put its `bin` on `PATH` and `share/pkgconfig` on `PKG_CONFIG_PATH`.
`BUILD_JOBS` controls build concurrency. The SWI tag emits a QLF warning about
an unrelated `json_rpc_common` file during its own build; the JSON bridge
library builds and is covered by the integration tests.

The Port backend finds `swipl` on `PATH`. Override with `SWIPL=/path/to/swipl`
or `SWI.start_link(backend: :port, swipl: "/path/to/swipl")`.
The native compiler uses `pkg-config swipl` and the running OTP's headers.
`make` builds `priv/swi_nif.so`; `mix compile` runs it automatically. Its runtime
search path comes from pkg-config's libdir, so custom prefixes work without
changing the system loader configuration. Set `ERL_INCLUDE` if needed.
`SWI_ELIXIR_SKIP_NIF=1 mix compile` supports a Port-only installation.
After changing SWI/OTP installations, run `make clean && mix compile`.

## Queries, loading, and ownership

```elixir
{:ok, prolog} = SWI.start_link(backend: :nif)
:ok = SWI.load(prolog, "examples/family.pl")
SWI.query(prolog, "family:ancestor(ada, Who)") |> Enum.to_list()
# Who = grace; alan; emmy
SWI.query(prolog, "between(1, inf, N)") |> Enum.take(10)
SWI.call(prolog, "repeat, fail", timeout: 50) # {:error, :timeout}
SWI.call(prolog, "throw(oops)") # {:error, {:prolog, "oops"}}
SWI.stop(prolog)
```

`query/3` returns a lazy Elixir enumerable of binding maps, including `%{}` for a
variable-free success and no elements for failure. It opens the query when
enumerated. `call/3` consumes one solution and returns `{:ok, boolean}` or
`{:error, reason}`. `load/3` consults a file and returns `:ok` or an error.
Goal text and paths must be UTF-8; invalid text raises `ArgumentError` in the
caller without touching the session. Queries contain exactly one goal, with an
optional final period and trailing comments. Extra terms are rejected before
execution. Failed initialization or directives make `load/3` return an error;
ordinary warnings remain nonfatal. A failed load can leave partial code and
side effects. Streams raise `SWI.Error` on Prolog or
transport errors, carrying the same `reason` returned by `call/3`.

Each session supports one active enumeration. Overlapping queries or loads
return `:busy`. The enumerating process owns the cursor; monitor cleanup closes
it if that process dies. Exhaustion, exceptions and `Enum.take/2` close it too.
Cleanup failures on early halt raise `SWI.Error`; `call/3` returns the error
instead of a successful Boolean. `stop/1` closes the active cursor and returns
`:ok` or a cleanup error. Closing and stopping are one server operation; later
queued requests exit when that session terminates. When an Elixir
consumer throws or raises, that original failure takes precedence and any
cleanup failure is logged. Cleanup failures after consumer death are logged;
native GC fallback failures are reported to stderr.

A suspended `Enumerable.reduce/3` continuation retains ownership until resumed
or halted; explicitly halt continuations you keep. Use separate sessions for
parallel searches. Variable IDs are local to a single answer.

`:timeout` defaults to 5,000 milliseconds and must be positive. It bounds each
solution search, excluding time spent consuming an answer. Consults also accept
a timeout. Ordinary SWI exceptions and alarm timeouts leave the session usable.
They do not roll back Prolog side effects. Elixir calls use an infinite GenServer
timeout so they cannot abandon a native call still executing in SWI.

Session option `:cleanup_timeout` is a positive integer in milliseconds
(default 1,000). For Port sessions, closing a cursor gets this budget plus one
second of transport grace, separately from the query's `:timeout`. This applies
to early halt, consumer death, explicit stop, and graceful supervisor shutdown.
If cleanup does not finish, the child is killed and its database is lost.

SWI runs `setup_call_cleanup/3` cleanup handlers with asynchronous signals
blocked. A SWI alarm therefore cannot bound even a pure Prolog loop in such a
handler. Native close, shutdown, and GC cleanup must wait for these handlers;
`:cleanup_timeout` does not enforce a native cleanup deadline. Use the Port
backend when cleanup requires a hard deadline. This limitation also applies to
cleanup triggered during a query timeout.

Startup checks protocol readiness and the JSON/time libraries before returning
a session. Port readiness has a two-second deadline. Startup errors include
`{:swipl_not_found, executable}`, `{:spawn_failed, diagnostic}`,
`{:startup, {:error, reason}}`, and `:nif_unavailable`. Bridge diagnostics are
also printed by SWI to stderr. `:bridge` can select a custom bridge file.
Invalid JSON, reply statuses, or encoded bindings return `:invalid_reply` and
retire the transport. A failed native bridge request likewise retires its
resource. The next request reconnects; callers must reload lost session state.
Native modules and ordinary predicates remain shared across native sessions.

For OTP supervision:

```elixir
children = [{SWI, backend: :port, name: MyProlog}]
{:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
SWI.call(MyProlog, "true")
```

Use `Supervisor.child_spec/2` with distinct IDs when starting multiple sessions.
On an external SWI crash or hard timeout, the Elixir session stays alive.
A request witnessing the failure returns its transport error, and a later
request reconnects. If the child dies while idle, the next query or load returns
`{:error, :session_reset}` once, before a subsequent request reconnects. An
existing suspended stream also reports that reset on its next pull. This
notice does not replay the rejected operation or reload source files. Coordinate
restoration with other users of the session: Port loaded files and asserted
state are lost; native ordinary predicates remain VM-wide after resource
retirement. Restarting the Elixir child under supervision creates a fresh
session. Monitor its concrete PID and reload state after `:DOWN`; a registered
name identifies whichever replacement is currently registered and carries no
database-generation guarantee.

## Values

| Prolog | Elixir |
| --- | --- |
| `hello` | `{:atom, "hello"}` |
| integer, float | integer, float |
| `"hello"` | `"hello"` |
| `[a,1]`, `[]` | `[{:atom, "a"}, 1]`, `[]` |
| `f(a,1)` | `{:compound, "f", [{:atom, "a"}, 1]}` |
| unbound variable | `{:var, integer_id}` |
| `[a\|tail]` | `{:cons, {:atom, "a"}, {:atom, "tail"}}` |
| cyclic term, dict, rational, other extended value | `{:prolog, rendered_text}` |

Binding names and atom names are binaries; arbitrary queries never intern BEAM
atoms. Shared unbound variables retain their identity across bindings and
compound arguments. Attributed-variable constraints are not serialized; query
or reify them explicitly in Prolog. Extended/cyclic values are an opaque text
fallback, not a round-trip AST. Inputs remain ordinary Prolog goal strings;
SWI parses them. Do not interpolate untrusted input or execute untrusted goals.

## Port versus NIF

Both backends use `priv/bridge.pl`, with an SWI engine retaining the query's
choice points. The deliberately small protocol has open/next/close/load
operations and tagged JSON values. OTP's built-in JSON handles decoding.
The NIF is a thin FLI call into that same bridge; it still uses serialization,
so lower latency is a measurement question rather than a promise.

Port runs the bridge in one persistent child. Ordinary goal output goes to
stderr; a separate output stream carries protocol replies. Its main thread
reads requests while a worker thread searches. EOF on the protocol input kills
the disposable runtime, including when the BEAM session is forcibly killed
mid-search. A hard transport
deadline (query timeout plus one second) kills the process even if its goal
catches the SWI alarm. This cannot guarantee Prolog cleanup handlers run.

NIF owns an FLI engine resource per session and executes initialization,
queries and explicit cleanup on dirty CPU schedulers. SWI engines attach and
detach between calls as dirty scheduler threads change. Concurrent sessions
have independent stacks and cursors; **SWI's modules and ordinary dynamic
predicate database are VM-wide**, not isolated. Use `thread_local/1` for query
scratch data. Source loading/reloading mutates shared code and should be
coordinated before concurrent searches. Query engines are children of session
engines: query-local flags and non-backtrackable variables do not persist
between queries. The query API promises persistent loaded code/database,
not interactive top-level thread state.

Native explicit close resumes and cuts suspended queries so cleanup exceptions
can propagate, then destroys their parent engine. A GC
fallback performs the same work on a short-lived native reaper thread, keeping
cleanup off normal BEAM schedulers. Native admission is bounded to **64 wrapper-owned engine
slots** per VM, including live resources, GC reclamations, and quarantined
engines. Exhaustion returns `{:error, :native_capacity}` from session startup.
Explicit close releases a slot only after confirmed engine destruction; failed
destruction retains the handle for retry. GC thread-creation or destruction
failure retains its slot in quarantine, prints a diagnostic, and reduces
capacity until VM restart. Blocked cleanup likewise occupies its slot. This
bounds reclamation work without pretending to interrupt native cleanup.
`SWI.Native.stats/0` provides internal engine/reaper/quarantine counts for
troubleshooting. Fault-injection switches are compiled only into isolated test
libraries; the normal NIF has no runtime fault switch. SWI and the NIF shared
library remain loaded for the VM lifetime; native hot upgrades/unloading are
not supported. SWI initializes with signal handling disabled to preserve
BEAM's signal handlers, and the wrapper never calls `PL_cleanup()`.

NIF timeouts use SWI alarms, which cannot forcibly stop foreign code that does
not service signals, or a goal that deliberately catches the alarm. A native
crash, `halt/1`, or process-wide Prolog operation affects the entire BEAM VM.
Choose Port when crash isolation or hard cancellation is required. Normal
BEAM scheduler responsiveness is tested with a real CPU search and with a
single ordinary scheduler.

The design follows SWI's official [FLI documentation](https://www.swi-prolog.org/pldoc/man?section=foreign),
[native engine rules](https://www.swi-prolog.org/pldoc/man?section=foreignthread),
and [Prolog engine interface](https://www.swi-prolog.org/pldoc/man?section=engines).

## Provers, learners, and Livebooks

`mix run examples/provers.exs` runs both [leanHaT](https://leancop.de/leanhat/)
and [nanoCoP-i-HT](https://www.leancop.de/ihat/) through both backends. Unmodified
SWI sources, copyright notices, archive hashes and adapter details are in
[vendor/README.md](vendor/README.md). Their upstream GPL licensing is preserved.

```elixir
:ok = SWI.load(prolog, "examples/leanhat.pl")
:ok = SWI.load(prolog, "examples/nanocop.pl")
SWI.call(prolog, ~s|leanhat:prove_text("p => p")|)
SWI.call(prolog, ~s|nanocop:prove_text("~p ; ~ ~p", ht)|)
SWI.call(prolog, ~s|nanocop:prove_text("~p ; ~ ~p", intu)|)
```

`call/3` stops at one proof. To enumerate a goal directly, bear in mind that
alternative proofs may be unbounded. `false` reports search exhaustion;
timeout never establishes non-validity. nanoCoP's HT extension is incomplete.

The [showcase provenance ledger](docs/prover-showcases.md) attributes formulas
to Jens Otten's TABLEAUX 2019 tutorial and Otten/Schaub's HT paper, and records
notation changes, expected results and diagnostic limitations.
`nanocop:prove_text/3` optionally returns the upstream connection proof;
leanHaT's adapter exposes success only.

Open the six standalone notebooks with an installed Livebook:

```sh
SWI_ELIXIR_PATH="$PWD" livebook server livebooks/
```

1. [Basic Prolog](livebooks/01_basic.livemd): unification, recursion, backend equality.
2. [Theorem proving](livebooks/02_provers.livemd): tutorial function chains and pigeonholes,
   HT versus intuitionistic logic, live kernel counters and nanoCoP proof terms.
3. [Search](livebooks/03_search.livemd): N-queens, lazy finite prefixes, an infinite generator.
4. [Backend comparison](livebooks/04_backends.livemd): startup, reuse, proving, timeouts and crashes.
5. [Metagol](livebooks/05_metagol.livemd): predicate invention, recursive ancestry,
   higher-order nested-list transformation and clause-budget experiments.
6. [Aleph](livebooks/06_aleph.livemd): Michalski’s trains, bottom clauses,
   mode declarations, memorization versus generalization, and recursive membership.

The ILP lessons execute the real upstream learners through both backends and
check learned programs on training and project-authored diagnostic cases.
[ILP provenance](docs/ilp-provenance.md) records authors, pinned commits, source
hashes, licenses and adaptations. Metagol is BSD-3-Clause; Aleph’s source carries
an academic-use notice and asks commercial users to contact its author.

## Validation and benchmarking

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
ERL_FLAGS='+S 1:1' mix test test/swi_test.exs
mix run examples/provers.exs
mix run examples/bench.exs
ERL_FLAGS='+S 1:1' mix test test/ilp_test.exs
mix run scripts/check_livebooks.exs
```

Tests cover binding/variable identity, recursion, large replies, exceptions,
alarm timeouts, hard Port timeouts, restart, independent native searches,
cleanup on early halt/consumer death/resource GC, scheduler responsiveness,
and ordinary/prover backend equivalence. Notebook code cells can be
validated twice in one VM without the UI using `scripts/check_livebooks.exs`;
the runner evaluates all six notebooks twice in one VM. This does not verify
Livebook rendering or interactive reruns.

[Benchmark output](docs/benchmark.txt) records a local run with startup,
persistent tiny/symbolic queries, 100 solutions, quantified calls to each
prover, median/p95 latency, timeout behavior, and Linux RSS snapshots.
RSS is a runtime/process snapshot, not a per-query allocation measurement;
BEAM allocator retention and VM-wide native state affect it. The benchmark
uses first proofs for theorem goals. No backend is assumed to be faster.
