:- module(leancop, []).
:- op(700, xfx, =).
:- include('../vendor/leanCoP/leancop21_swi.pl').
:- include('../vendor/leanCoP/leancop_tptp2.pl').
:- thread_local lit/4, pathlim/0.

prove_text(Text) :- prove_text(Text, _).

prove_text(Text, Proof) :-
    swi_bridge:read_goal(Text, leancop, Formula, _),
    leancop_equal(Formula, Problem),
    call_cleanup(once(prove(Problem, Proof)),
                 (retractall(lit(_,_,_,_)), retractall(pathlim))).
