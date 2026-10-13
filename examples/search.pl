:- module(search, [queens/2]).
:- use_module(library(clpfd)).
queens(N, Rows) :-
    length(Rows, N), Rows ins 1..N,
    safe(Rows), labeling([ff], Rows).
safe([]).
safe([Q|Qs]) :- diagonals(Qs, Q, 1), safe(Qs).
diagonals([], _, _).
diagonals([Q|Qs], Q0, D) :-
    Q0 #\= Q, abs(Q0-Q) #\= D, D1 #= D+1, diagonals(Qs, Q0, D1).
