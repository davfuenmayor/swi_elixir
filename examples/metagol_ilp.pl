% Adapted from Metagol's README, kinship2.pl and droplasts.pl.
% Copyright (c) 2016, Metagol authors; BSD-3-Clause (vendor/metagol/LICENSE).
% Namespaced primitives and evaluation are project additions.
:- module(metagol_ilp, [learn_task/7]).
:- use_module('../vendor/metagol/metagol').
:- use_module(ilp_support).

% Upstream Metagol resolves primitives in user. Prefix these demonstration hooks.
user:mg_mother(A,B) :- metagol_tasks:mg_mother(A,B).
user:mg_father(A,B) :- metagol_tasks:mg_father(A,B).
user:mg_parent(A,B) :- metagol_tasks:mg_parent(A,B).
user:mg_tail(A,B) :- metagol_ilp:mg_tail(A,B).
user:mg_reverse(A,B) :- metagol_ilp:mg_reverse(A,B).

metarule(identity, [P,Q], [P,A,B], [[Q,A,B]]).
metarule(chain, [P,Q,R], [P,A,B], [[Q,A,C],[R,C,B]]).
metarule(tailrec, [P,Q], [P,A,B], [[Q,A,C],[P,C,B]]).
metarule(tohigherorder, [P,Q,F], [P,A,B], [[Q,A,B,F]]).
:- if(\+ clause(metagol:ibk([map,[],[],_],[],_), true)).
ibk([map,[],[],_], []).
ibk([map,[A|As],[B|Bs],F], [[F,A,B],[map,As,Bs,F]]).
:- endif.

% Runtime implementation of the interpreted map for executing learned clauses.
map([], [], _).
map([A|As], [B|Bs], F) :- call(F,A,B), map(As,Bs,F).
mg_tail([_|T], T).
mg_reverse(A,B) :- reverse(A,B).

% Task facts and examples are loaded separately by each consumer.

% These examples share Metagol's upstream registry. Serialize learning and restore
% user declarations/settings; the native runtime shares modules across sessions.
learn_task(Task, Limit, Status, ProgramText, Rows, Clauses, Trace) :-
    must_be(integer, Limit), between(1,6,Limit), metagol_tasks:primitives(Task, Primitives),
    with_mutex(metagol_ilp,
      setup_call_cleanup(
        (metagol:options, save_settings(Saved)),
        with_output_to(string(Trace),
        (configure(Primitives, Limit), metagol_tasks:training(Task, Pos, Neg), metagol_tasks:tests(Task, Tests),
         (once(metagol:learn(Pos, Neg, MetaProgram)) ->
           Status = learned,
           reverse(MetaProgram, Ordered),
           maplist(metagol:metasub_to_clause, Ordered, Program),
           length(Program, Clauses), program_text(Program, ProgramText),
           with_program(metagol_ilp, Program,
             evaluate(metagol_ilp, Pos, Neg, Tests, Rows))
         ; Status = no_hypothesis, Clauses = 0, ProgramText = "", Rows = []))),
        restore_settings(Saved))).

save_settings(settings(Body, Options, Functional)) :-
    findall(P, user:body_pred(P), Body),
    findall(O, (option_pattern(O), functor(O,N,A), current_predicate(metagol:N/A), call(metagol:O)), Options),
    (metagol:functional -> Functional = true ; Functional = false).
option_pattern(max_clauses(_)).
option_pattern(min_clauses(_)).
option_pattern(max_inv_preds(_)).

configure(Primitives, Limit) :-
    retractall(user:body_pred(_)),
    forall(member(P,Primitives), assertz(user:body_pred(P))),
    metagol:set_option(min_clauses(1)), metagol:set_option(max_clauses(Limit)),
    N is Limit-1, metagol:set_option(max_inv_preds(N)), retractall(metagol:functional).

restore_settings(settings(Body, Options, Functional)) :-
    retractall(user:body_pred(_)),
    forall(member(P,Body), assertz(user:body_pred(P))),
    forall(option_pattern(O), retractall(metagol:O)),
    forall(member(O,Options), assertz(metagol:O)),
    retractall(metagol:functional),
    (Functional == true -> assertz(metagol:functional) ; true).
