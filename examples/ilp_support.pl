% Project-authored display and evaluation helpers; no learning algorithm here.
:- module(ilp_support, [program_text/2, evaluate/5, with_program/3]).
:- meta_predicate with_program(+, +, 0).

program_text(Program, Text) :-
    with_output_to(string(Text), maplist(portray_clause, Program)).

% Reference-based cleanup leaves background knowledge intact, including on error.
with_program(Module, Program, Goal) :-
    setup_call_cleanup(
      findall(Ref, (member(Clause, Program), assertz(Module:Clause, Ref)), Refs),
      Goal,
      maplist(erase, Refs)).

evaluate(Module, Pos, Neg, Tests, Rows) :-
    findall(result(Split, Text, Expected, Actual),
      (example(Pos, Neg, Tests, Split, Goal, Expected),
       with_output_to(string(Text), write_term(Goal, [quoted(true)])),
       (once(Module:Goal) -> Actual = true ; Actual = false)), Rows).

example(Pos, _, _, train, Goal, true) :- member(Goal, Pos).
example(_, Neg, _, train, Goal, false) :- member(Goal, Neg).
example(_, _, Tests, test, Goal, Expected) :- member(Goal-Expected, Tests).
