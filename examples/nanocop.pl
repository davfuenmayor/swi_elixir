:- module(nanocop, [prove_text/2, prove_text/3]).
% The translator changes '=' precedence. Restore it before reconsulting core.
:- op(700, xfx, =).
% Keep the upstream load-time directive from changing the caller's flag.
:- current_prolog_flag(occurs_check, Flag), nb_setval(nanocop_load_flag, Flag).
:- include('../vendor/nanoCoP-i-HT/nanocopi20_swi.pl').
:- nb_getval(nanocop_load_flag, Flag), set_prolog_flag(occurs_check, Flag),
   nb_delete(nanocop_load_flag).
:- include('../vendor/nanoCoP-i-HT/nanocop_tptp2.pl').
% Upstream uses a dynamic scratch database. Each query engine owns its copy.
:- thread_local lit/4, pathlim/0.

prove_text(Text, Logic) :- prove_text(Text, Logic, _).

prove_text(Text, Logic, Proof) :-
    memberchk(Logic, [intu, ht]),
    setup_call_cleanup(
      (current_prolog_flag(occurs_check, Previous), set_prolog_flag(occurs_check, true)),
      (swi_bridge:read_goal(Text, nanocop, F, _),
       leancop_equal(F, Equal), leancop_intermed(Equal, Logic, Problem), prove(Problem, Proof)),
      set_prolog_flag(occurs_check, Previous)).
