%% File: nanocop_tptp2.pl  -  Version: 1.1im  -  Date: 1 April 2025
%%
%% Purpose: 1. Translate formula from TPTP into leanCoP syntax
%%          2. Add equality axioms to the given formula
%%          3. Add intermediate axioms to the given formula
%%
%% Author:  Jens Otten
%% Web:     www.leancop.de/nanocop/
%%
%% Usage: leancop_tptp2(X,F). % where X is a problem file using TPTP
%%                            %  syntax and F the translated formula
%%        leancop_equal(F,G). % where F is a formula and G the
%%                            %  formula with added equality axioms
%%    leancop_intermed(F,L,G) % where F is a formula and G is F
%%                            %  with added axioms for the logic L
%%
%% Copyright: (c) 2009-2025 by Jens Otten
%% License:   GNU General Public License


% definitions of logical connectives and quantifiers

% leanCoP syntax
:- op(1130, xfy, <=>). % equivalence
:- op(1110, xfy, =>).  % implication
%                      % disjunction (;)
%                      % conjunction (,)
:- op( 500, fy, ~).    % negation
:- op( 500, fy, all).  % universal quantifier
:- op( 500, fy, ex).   % existential quantifier
:- op( 500,xfy, :).

% TPTP syntax
:- op(1130, xfy, <~>).  % negated equivalence
:- op(1110, xfy, <=).   % implication
:- op(1100, xfy, '|').  % disjunction
:- op(1100, xfy, '~|'). % negated disjunction
:- op(1000, xfy, &).    % conjunction
:- op(1000, xfy, ~&).   % negated conjunction
:- op( 500, fy, !).     % universal quantifier
:- op( 500, fy, ?).     % existential quantifier
:- op( 400, xfx, =).    % equality
:- op( 300, xf, !).     % negated equality (for !=)
:- op( 299, fx, $).     % for $true/$false

% TPTP syntax to leanCoP syntax mapping

op_tptp2((A<=>B),(A1<=>B1),   [A,B],[A1,B1]).
op_tptp2((A<~>B),~((A1<=>B1)),[A,B],[A1,B1]).
op_tptp2((A=>B),(A1=>B1),     [A,B],[A1,B1]).
op_tptp2((A<=B),(B1=>A1),     [A,B],[A1,B1]).
op_tptp2((A|B),(A1;B1),       [A,B],[A1,B1]).
op_tptp2((A'~|'B),~((A1;B1)), [A,B],[A1,B1]).
op_tptp2((A&B),(A1,B1),       [A,B],[A1,B1]).
op_tptp2((A~&B),~((A1,B1)),   [A,B],[A1,B1]).
op_tptp2(~A,~A1,[A],[A1]).
op_tptp2((! [V]:A),(all V:A1),     [A],[A1]).
op_tptp2((! [V|Vars]:A),(all V:A1),[! Vars:A],[A1]).
op_tptp2((? [V]:A),(ex V:A1),      [A],[A1]).
op_tptp2((? [V|Vars]:A),(ex V:A1), [? Vars:A],[A1]).
op_tptp2($true,(true___=>true___),      [],[]).
op_tptp2($false,(false___ , ~ false___),[],[]).
op_tptp2(A=B,~(A1=B),[],[]) :- \+var(A), A=(A1!).
op_tptp2(P,P,[],[]).


%%% translate into leanCoP syntax

leancop_tptp2(File,F) :- leancop_tptp2(File,'',[_],F,_).

leancop_tptp2(File,AxPath,AxNames,F,Con) :-
    open(File,read,Stream), ( fof2cop(Stream,AxPath,AxNames,A,Con)
    -> close(Stream) ; close(Stream), fail ),
    ( Con=[] -> F=A ; A=[] -> F=Con ; F=(A=>Con) ).

fof2cop(Stream,AxPath,AxNames,F,Con) :-
    read(Stream,Term),
    ( Term=end_of_file -> F=[], Con=[] ;
      ( Term=..[fof,Name,Type,Fml|_] ->
        ( \+member(Name,AxNames) -> true ; fml2cop([Fml],[Fml1]) ),
        ( Type=conjecture -> Con=Fml1 ; Con=Con1 ) ;
        ( Term=include(File), AxNames2=[_] ;
          Term=include(File,AxNames2) ) -> name(AxPath,AL),
          name(File,FL), append(AL,FL,AxL), name(AxFile,AxL),
          leancop_tptp2(AxFile,'',AxNames2,Fml1,_), Con=Con1
      ), fof2cop(Stream,AxPath,AxNames,F1,Con1),
      ( Term=..[fof,N,Type|_], (Type=conjecture;\+member(N,AxNames))
      -> (F1=[] -> F=[] ; F=F1) ; (F1=[] -> F=Fml1 ; F=(Fml1,F1)) )
    ).

fml2cop([],[]).
fml2cop([F|Fml],[F1|Fml1]) :-
    op_tptp2(F,F1,FL,FL1) -> fml2cop(FL,FL1), fml2cop(Fml,Fml1).


%%% add intermediate logic axioms

leancop_intermed(F,L,F1) :-
    collect_proppred([F],PL), add_negpred(PL,PLN),
    ( L=jankov -> imed_jan_axioms(PL,F2) ;
      L=goedel -> imed_goe_axioms(PL,PL,PL,F3),
                  imed_jan_axioms(PL,F4),
                  ( F3=[] -> F2=F4 ; F2=(F3,F4) ) ;
      L=ht     -> imed_hat_axioms(PLN,PL,PLN,F3),
                  imed_htq_axioms(PLN,F4),
                  ( F3=[] -> F2=F4 ; F4=[] -> F2=F3 ; F2=(F3,F4) ) ;
      L=classic-> imed_cla_axioms(PL,F2) ; true ),
    ( F2=[] -> F1=F ; F=(A=>C) -> F1=((F2,A)=>C) ; F1=(F2=>F) ).

% generate intermediate logic axioms

% Jankov axioms ( -p v - -p )
imed_jan_axioms([],[]).
imed_jan_axioms([(P,I)|PL],F) :-
    inter_axiom(A,C,E,I), imed_jan_axioms(PL,F1), P1=..[P|C],
    E=(~P1 ; ~ ~P1), ( F1=[] -> F=A ; F=(A,F1) ).

% Goedel axioms ( (p -> q) v ((p -> q) -> p) )
imed_goe_axioms([],[_],_,[]).
imed_goe_axioms([],[_,(Q,J)|QL],PL,F) :-
    imed_goe_axioms(PL,[(Q,J)|QL],PL,F).
imed_goe_axioms([(P,I)|PL],[(P,I)|QL],PL1,F) :- !,
    imed_goe_axioms(PL,[(P,I)|QL],PL1,F).
imed_goe_axioms([(P,I)|PL],[(Q,J)|QL],PL1,F) :-
    inter_axiom(A,C,B,I), inter_axiom(B,D,E,J),
    imed_goe_axioms(PL,[(Q,J)|QL],PL1,F1), P1=..[P|C], Q1=..[Q|D],
    E=( (P1=>Q1) ; ((P1=>Q1) => P1) ), ( F1=[] -> F=A ; F=(A,F1) ).

% HT axioms ( p v (p -> q) v -q )
imed_hat_axioms([],[_],_,[]).
imed_hat_axioms([],[_,(Q,J)|QL],PL,F) :-
    imed_hat_axioms(PL,[(Q,J)|QL],PL,F).
imed_hat_axioms([(P,I)|PL],[(P,I)|QL],PL1,F) :- !,
    imed_hat_axioms(PL,[(P,I)|QL],PL1,F).
imed_hat_axioms([(P,I)|PL],[(Q,J)|QL],PL1,F) :-
    inter_axiom(A,C,B,I), inter_axiom(B,D,E,J),
    imed_hat_axioms(PL,[(Q,J)|QL],PL1,F1),
    ( P=(~P2) -> P1=(~P3) ; P2=P, P1=P3 ), P3=..[P2|C],
    ( Q=(~Q2) -> Q1=(~Q3) ; Q2=Q, Q1=Q3 ), Q3=..[Q2|D],
    E=( P1 ; (P1=>Q1) ; ~Q1 ), ( F1=[] -> F=A ; F=(A,F1) ).

% HT axioms ( ex X ( p(X) -> all X p(X) ) )
imed_htq_axioms([],[]).
imed_htq_axioms([(_,0)|PL],F) :- !, imed_htq_axioms(PL,F).
imed_htq_axioms([(P,I)|PL],F) :-
    ( P=(~P3) -> P1=(~P4), P2=(~P5) ; P3=P, P1=P4, P2=P5 ),
    imed_htq_axioms(PL,F1), inteq_axiom(A,C,E,I), P4=..[P3|C],
    inter_axiom(B,D,P2,I), P5=..[P3|D], E=(P1=>B),
    ( F1=[] -> F=A ; F=(A,F1) ).

% Classical axioms ( p v -p )
imed_cla_axioms([],[]).
imed_cla_axioms([(P,I)|PL],F) :-
    inter_axiom(A,C,E,I), imed_cla_axioms(PL,F1), P1=..[P|C],
    E=(P1 ; ~P1), ( F1=[] -> F=A ; F=(A,F1) ).

inter_axiom(E,[],E,0).
inter_axiom(A,[X|C],E,I) :-
    I>0, I1 is I-1, inter_axiom(A1,C,E,I1), A=(all X:A1).

inteq_axiom(E,[],E,0).
inteq_axiom(A,[X|C],E,I) :-
    I>0, I1 is I-1, inteq_axiom(A1,C,E,I1), A=(ex X:A1).

% collect propositional and predicate symbols

collect_proppred([],[]).
collect_proppred([F|Fml],PL) :-
    ( ( F=..[<=>|F1] ; F=..[=>|F1] ; F=..[;|F1] ; F=..[','|F1] ;
        F=..[~|F1] ; (F=..[all,_:F2] ; F=..[ex,_:F2]), F1=[F2] ) ->
      collect_proppred(F1,PL1) ; F=..[P|Arg], length(Arg,I),
      PL1=[(P,I)] ), collect_proppred(Fml,PL2), union1(PL1,PL2,PL).

add_negpred([],[]).
add_negpred([(P,I)|PL],[(P,I),(~P,I)|PL1]) :- add_negpred(PL,PL1).


%%% add equality axioms

leancop_equal(F,F1) :-
    collect_predfunc([F],PL,FL), append(PL2,[(=,2)|PL3],PL),
    append(PL2,PL3,PL1) -> basic_equal_axioms(F0),
    subst_pred_axioms(PL1,F2), (F2=[] -> F3=F0 ; F3=(F0,F2)),
    subst_func_axioms(FL,F4), (F4=[] -> F5=F3 ; F5=(F3,F4)),
    ( F=(A=>C) -> F1=((F5,A)=>C) ; F1=(F5=>F) ) ; F1=F.

basic_equal_axioms(F) :-
    F=(( all X:(X=X) ),
       ( all X:all Y:((X=Y)=>(Y=X)) ),
       ( all X:all Y:all Z:(((X=Y),(Y=Z))=>(X=Z)) )).

% generate substitution axioms

subst_pred_axioms([],[]).
subst_pred_axioms([(P,I)|PL],F) :-
    subst_axiom(A,B,C,D,E,I), subst_pred_axioms(PL,F1), P1=..[P|C],
    P2=..[P|D], E=(B,P1=>P2), ( F1=[] -> F=A ; F=(A,F1) ).

subst_func_axioms([],[]).
subst_func_axioms([(P,I)|FL],F) :-
    subst_axiom(A,B,C,D,E,I), subst_func_axioms(FL,F1), P1=..[P|C],
    P2=..[P|D], E=(B=>(P1=P2)), ( F1=[] -> F=A ; F=(A,F1) ).

subst_axiom((all X:all Y:E),(X=Y),[X],[Y],E,1).
subst_axiom(A,B,[X|C],[Y|D],E,I) :-
    I>1, I1 is I-1, subst_axiom(A1,B1,C,D,E,I1),
    A=(all X:all Y:A1), B=((X=Y),B1).

% collect predicate & function symbols

collect_predfunc([],[],[]).
collect_predfunc([F|Fml],PL,FL) :-
    ( ( F=..[<=>|F1] ; F=..[=>|F1] ; F=..[;|F1] ; F=..[','|F1] ;
        F=..[~|F1] ; (F=..[all,_:F2] ; F=..[ex,_:F2]), F1=[F2] ) ->
      collect_predfunc(F1,PL1,FL1) ; F=..[P|Arg], length(Arg,I),
      I>0 ->  PL1=[(P,I)], collect_func(Arg,FL1) ; PL1=[], FL1=[] ),
    collect_predfunc(Fml,PL2,FL2),
    union1(PL1,PL2,PL), union1(FL1,FL2,FL).

collect_func([],[]).
collect_func([F|FunL],FL) :-
    ( \+var(F), F=..[F1|Arg], length(Arg,I), I>0 ->
      collect_func(Arg,FL1), union1([(F1,I)],FL1,FL2) ; FL2=[] ),
    collect_func(FunL,FL3), union1(FL2,FL3,FL).

union1([],L,L).
union1([H|L1],L2,L3) :- member(H,L2), !, union1(L1,L2,L3).
union1([H|L1],L2,[H|L3]) :- union1(L1,L2,L3).

