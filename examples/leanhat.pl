:- module(leanhat, [prove_text/1]).
% The translator changes '=' precedence; restore it before reloading core.
:- op(700, xfx, =).
:- include('../vendor/leanHaT/leanhat_swi.pl').
:- include('../vendor/leanHaT/nanocop_tptp2.pl').

prove_text(Text) :-
    swi_bridge:read_goal(Text, leanhat, F, _), leancop_equal(F, Problem), prove(Problem).
