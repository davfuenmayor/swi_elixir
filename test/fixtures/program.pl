:- module(fixture, [path/2, spin/0]).
edge(a, b).
edge(b, c).
edge(c, d).
path(A, B) :- edge(A, B).
path(A, B) :- edge(A, C), path(C, B).
spin :- spin.
