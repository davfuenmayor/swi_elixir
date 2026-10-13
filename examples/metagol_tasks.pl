% Adapted from Metagol examples; see docs/ilp-provenance.md.
% Copyright (c) 2016, Metagol authors; BSD-3-Clause (vendor/metagol/LICENSE).
:- module(metagol_tasks, [primitives/2, training/3, tests/2]).

mg_mother(ann,amy). mg_mother(ann,andy). mg_mother(amy,amelia).
mg_mother(linda,gavin). mg_mother(nora,ivy).
mg_father(steve,amy). mg_father(steve,andy). mg_father(gavin,amelia).
mg_father(andy,spongebob). mg_father(ivy,leo).

mg_parent(queen_victoria,edward_seventh).
mg_parent(edward_seventh,george_fifth).
mg_parent(george_fifth,george_sixth).
mg_parent(george_sixth,elizabeth_second).
mg_parent(queen_mother,elizabeth_second).
mg_parent(elizabeth_second,prince_charles).
mg_parent(prince_philip,prince_charles).
mg_parent(prince_charles,prince_william).
mg_parent(prince_charles,prince_harry).
mg_parent(princess_diana,prince_william).
mg_parent(princess_diana,prince_harry).
mg_parent(prince_william,prince_george).

primitives(grandparent, [mg_mother/2,mg_father/2]).
primitives(ancestor, [mg_parent/2]).
primitives(droplasts, [mg_tail/2,mg_reverse/2]).

training(grandparent,
 [grandparent(ann,amelia),grandparent(steve,amelia),grandparent(ann,spongebob),
  grandparent(steve,spongebob),grandparent(linda,amelia)],
 [grandparent(amy,amelia)]).
training(ancestor,
 [ancestor(elizabeth_second,prince_charles),ancestor(george_sixth,prince_harry),
  ancestor(queen_mother,prince_william)], []).
training(droplasts,
 [droplasts([[a,b,c],[d,e,f,g]],[[a,b],[d,e,f]]),
  droplasts([[h,i],[j,k,l],[m,n,o,p]],[[h],[j,k],[m,n,o]])],
 [droplasts([[a,b,c]],[[b,c]])]).

tests(grandparent,
 [grandparent(nora,leo)-true, grandparent(ann,gavin)-false,
  grandparent(ann,ann)-false]).
tests(ancestor,
 [ancestor(queen_victoria,prince_george)-true,
  ancestor(princess_diana,prince_george)-true,
  ancestor(prince_george,queen_victoria)-false, ancestor(queen_victoria,queen_victoria)-false]).
tests(droplasts,
 [droplasts([[q],[r,s,t,u,v],[]],[[],[r,s,t,u],[]])-false,
  droplasts([[q],[r,s,t,u,v]],[[],[r,s,t,u]])-true,
  droplasts([],[])-true, droplasts([[x,y]],[[y]])-false]).
