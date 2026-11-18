:- module(ileancop, []).
:- include('../vendor/ileanCoP/ileancop_swi.pl').
:- thread_local pathlim/0.

prove_text(Text) :-
    swi_bridge:read_goal(Text, ileancop, Formula, _),
    make_matrix_intu(Formula, Matrix),
    call_cleanup(once(prove(Matrix, 1)), retractall(pathlim)).
