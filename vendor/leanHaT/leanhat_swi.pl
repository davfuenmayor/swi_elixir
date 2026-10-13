%% File: leanhat_swi.pl  -  Version: 1.0  -  Date: 1 April 2025
%%
%% Purpose: leanHaT: A Sequent Prover for the Logic of HT
%%
%% Author:  Jens Otten
%% Web:     www.leancop.de/leanhat/
%%
%% Usage:   prove(F).    % where F is a first-order formula, e.g.
%%                       %  F=((p,all X:(p=>q(X)))=>all Y:q(Y))
%%
%% Copyright: (c) 2025 by Jens Otten
%% License:   GNU General Public License

% definitions of logical connectives and quantifiers

:- op(1130, xfy, <=>). :- op(1110, xfy, =>). :- op(500, fy, ~).
:- op( 500,  fy, all). :- op( 500,  fy, ex). :- op(500,xfy, :).


% -----------------------------------------------------------------
% prove(F,Proof) - prove formula F

prove(F) :- univar(F,[],F1), prove(F1,1).

prove(F,I) :- prove([]>[F],s,[],I).
prove(F,I) :- \+ no_mul([([F],0)]), I1 is I+1, prove(F,I1).

% -----------------------------------------------------------------
% fml(F,Pol,L1>R1,L2>R2,L3>R3,S,FreeV,NewX,Cpy1,Cpy2)
% - specification of sequent rules
%
% F: formula, Pol:polarity, S:position, FreeV: free variable
% NewX: new free variable, Cpy1: to be copied and unified with Cpy2
% Ln>Rn: add to left/right side of 1st/2nd/3rd premise (n=1,2,3)

fml((A,B),    1, [A,B] > [],   [] > [],     [] > [], _,_,[],[],[]).
fml((A;B),    0, [] > [A,B],   [] > [],     [] > [], _,_,[],[],[]).
fml(~ (A,B),  0, [] > [~A,~B], [] > [],     [] > [], _,_,[],[],[]).
fml(~ (A;B),  1, [~A,~B] > [], [] > [],     [] > [], _,_,[],[],[]).
fml(~ (A=>B), 1, [~B] > [~A],  [] > [],     [] > [], _,_,[],[],[]).
fml(~ (~A),   1, [] > [~A],    [] > [],     [] > [], _,_,[],[],[]).
fml(~ (~A),   0, [~A] > [],    [] > [],     [] > [], _,_,[],[],[]).

fml((A,B),    0, [] > [A],     [] > [B],    [] > [], _,_,[],[],[]).
fml((A;B),    1, [A] > [],     [B] > [],    [] > [], _,_,[],[],[]).
fml(~ (A,B),  1, [~A] > [],    [~B] > [],   [] > [], _,_,[],[],[]).
fml(~ (A;B),  0, [] > [~A],    [] > [~B],   [] > [], _,_,[],[],[]).
fml(~ (A=>B), 0, [~A] > [],    [] > [~B],   [] > [], _,_,[],[],[]).
fml((A=>B),   0, [A] > [B],    [~B] > [~A], [] > [], _,_,[],[],[]).
fml((A=>B),   1, [~A] > [],    [] > [A,~B], [B]>[],  _,_,[],[],[]).

fml((A<=>B),  1, [((A=>B),(B=>A))] > [],[]>[],[]>[], _,_,[],[],[]).
fml((A<=>B),  0, [] > [((A=>B),(B=>A))],[]>[],[]>[], _,_,[],[],[]).
fml(~ (A<=>B),1, [~ ((A=>B),(B=>A))]>[],[]>[],[]>[], _,_,[],[],[]).
fml(~ (A<=>B),0, []>[~ ((A=>B),(B=>A))],[]>[],[]>[], _,_,[],[],[]).

fml(~all X:A, 1, [~C] > [], []>[], []>[],  S,FV,[],(X,A),(S^FV,C)).
fml(~ex X:A,  0, [] > [~C], []>[], []>[],  S,FV,[],(X,A),(S^FV,C)).
fml( all X:A, 0, [] > [C],  []>[], []>[],  S,FV,[],(X,A),(S^FV,C)).
fml( ex X:A,  1, [C] > [],  []>[], []>[],  S,FV,[],(X,A),(S^FV,C)).

fml(~all X:A, 0, [] > [~C,~all X:A], []>[],[]>[], _,_,[Y],X:A,Y:C).
fml(~ex X:A,  1, [~C,~ex X:A] > [],  []>[],[]>[], _,_,[Y],X:A,Y:C).
fml( all X:A, 1, [C,all X:A] > [],   []>[],[]>[], _,_,[Y],X:A,Y:C).
fml( ex X:A,  0, [] > [C,ex X:A],    []>[],[]>[], _,_,[Y],X:A,Y:C).

% -----------------------------------------------------------------
% prove(Left>Right,S,FreeV,VarLim) - proof search

prove(Left>Right,_,_,_) :-
    member(A,Left), ( member(B,Right) ; member(~B,Left) ), ( A==B ->
    ! ; ( A=(~C) ->  C=..[P|_] ; A=..[P|_] ), P\=',', P\=';', P\='~',
    P\='=>', P\='<=>', P\=all, P\=ex, unify_with_occurs_check(A,B) ).

prove(Left>Right,S,FreeV,VarLim) :-
    fml(F,Pol,L1>R1,L2>R2,L3>R3,S,FreeV,V,Cpy1,Cpy2),
    ( Pol=1, append(LeftA,[F|LeftB],Left), RightA=Right, RightB=[] ;
      Pol=0, append(RightA,[F|RightB],Right), LeftA=Left, LeftB=[] ),
    ( V=[] -> ! ; \+ length(FreeV,VarLim) ),
    append(FreeV,V,FreeV1), copy_term((Cpy1,FreeV),(Cpy2,FreeV)),
    append(LeftA,LeftB,L0), append(RightA,RightB,R0),
    append(L1,L0,Left1), append(R1,R0,Right1), append(L2,L0,Left2),
    append(R2,R0,Right2), append(L3,L0,Left3), append(R3,R0,Right3),
    prove(Left1>Right1,l(S),FreeV1,VarLim),
    ( L2=[],R2=[] -> true ; prove(Left2>Right2,r(S),FreeV1,VarLim) ),
    ( L3=[],R3=[] -> true ; prove(Left3>Right3,x(S),FreeV1,VarLim) ).

% -----------------------------------------------------------------
% no_mul([FList]) - check multiplicities in FList

no_mul([]).
no_mul([([F,G],Pol)|T]) :- !, no_mul([([F],Pol),([G],Pol)|T]).
no_mul([([F],Pol)|T]) :-
    fml(F,Pol,L1>R1,L2>R2,_,_,_,V,U,U), !, V==[],
    no_mul([(L1,1),(R1,0),(L2,1),(R2,0)|T]).
no_mul([_|T]):- no_mul(T).

% -----------------------------------------------------------------
% univar(F,[],F1) - create unique variable names in F, return F1

univar(X,_,X)  :- (atomic(X);var(X);X==[[]]), !.
univar(F,Q,F1) :-
    F=..[A,B|T], ( (A=ex;A=all),B=X:C -> delete2(Q,X,Q1),
    copy_term((X,C,Q1),(Y,D,Q1)), univar(D,[Y|Q],E), F1=..[A,Y:E] ;
    univar(B,Q,B1), univar(T,Q,T1), F1=..[A,B1|T1] ).

% delete variable from list
delete2([],_,[]).
delete2([X|T],Y,T1) :- X==Y, !, delete2(T,Y,T1).
delete2([X|T],Y,[X|T1]) :- delete2(T,Y,T1).
