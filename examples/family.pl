:- module(family, [ancestor/2]).
parent(ada, grace).
parent(grace, alan).
parent(alan, emmy).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
