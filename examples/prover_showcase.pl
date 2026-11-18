% Project-authored diagnostics; prover algorithms remain in unchanged vendor files.
:- module(prover_showcase, [run/7, source/3]).
:- use_module(library(prolog_wrap)).
:- use_module(leancop, []).
:- use_module(leanhat, []).
:- use_module(ileancop, []).

core(leancop, leancop:prove(_,_,_,_,_,_), leancop:prove/6).
core(leanhat, leanhat:prove(_,_,_,_), leanhat:prove/4).
core(ileancop, ileancop:prove(_,_,_,_,_), ileancop:prove/5).

source(Prover, File, Line) :-
    core(Prover, Head, _), clause(Head, _, Ref),
    clause_property(Ref, file(File)), clause_property(Ref, line_count(Line)), !.

% Run serially: wrappers modify predicates shared by all embedded engines.
% The counter itself belongs to the calling query engine.
run(Prover, Logic, Text, Result, Calls, Inferences, Proof) :-
    core(Prover, Head, PI),
    setup_call_cleanup(
      (nb_setval(showcase_calls, 0),
       wrap_predicate(Head, showcase, Wrapped,
         (prover_showcase:count, call(Wrapped)))),
      (statistics(inferences, Before),
       (once(search(Prover, Logic, Text, Proof)) -> Result = proved
       ; Result = exhausted, Proof = none),
       statistics(inferences, After), Inferences is After-Before,
       nb_getval(showcase_calls, Calls)),
      (unwrap_predicate(PI, showcase), nb_delete(showcase_calls))).

count :-
    (nb_current(showcase_calls, N) -> N1 is N+1, nb_setval(showcase_calls, N1) ; true).

search(leancop, classical, Text, Proof) :- leancop:prove_text(Text, Proof).
search(leanhat, ht, Text, unavailable) :- leanhat:prove_text(Text).
search(ileancop, intu, Text, unavailable) :- ileancop:prove_text(Text).
