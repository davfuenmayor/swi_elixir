%% File: nanocopi_main.pl  -  Version: 2.1im  -  Date: 1 April 2025
%%
%% Purpose: Call the nanoCoP-i core prover for a given formula
%%
%% Author:  Jens Otten
%% Web:     www.leancop.de/nanocop-i/
%%
%% Usage:   nanocopi_main(X,S,R). % prove formula in file X with
%%                                %  settings S and returns result R
%%
%% Copyright: (c) 2017-2025 by Jens Otten
%% License:   GNU General Public License

:- assert(prolog(swi)).  % Prolog dialect (eclipse/swi)
:- assert(logic(intu)).  % Logic (intu|jankov|goedel|hat]
:- dynamic(axiom_path/1).

% execute predicates specific to Prolog dialect

:- \+ prolog(eclipse) -> true ;
   nodbgcomp,  % switch off debugging mode
   set_flag(print_depth,10000),  % set print depth
   set_flag(variable_names,off),  % print internal variable names
   ( getenv('TPTP',Path) -> Path1=Path ; Path1='' ),
   retract_all(axiom_path(_)), assert(axiom_path(Path1)),
   [nanocopi20].  % load nanoCoP-i core prover

:- prolog(eclipse) -> true ;
   set_prolog_flag(print_write_options,[quoted(false)]),
   ( getenv('TPTP',Path) -> Path1=Path ; Path1='' ),
   retractall(axiom_path(_)), assert(axiom_path(Path1)),
   [nanocopi20_swi].  % load nanoCoP-i core prover

% load additional nanoCoP-i components

:- [nanocopi_proof]. % load program for proof presentation
:- [nanocop_tptp2].  % load module to support TPTP syntax

%%% call the nanoCoP-i core prover

nanocopi_main(File,Settings,Result) :-
    axiom_path(AxPath), ( AxPath='' -> AxDir='' ;
    name(AxPath,AxL), append(AxL,[47],DirL), name(AxDir,DirL) ),
    ( leancop_tptp2(File,AxDir,[_],F,Conj) ->
      Problem=F ; [File], f(Problem), Conj=non_empty ),
    ( Conj\=[] -> Problem1=Problem ; Problem1=(~Problem) ),
    ( member(noeq,Settings) -> Problem1=Problem2 ;
        leancop_equal(Problem1,Problem2) ),
    logic(Logic), leancop_intermed(Problem2,Logic,Problem3),
    ( prove2(Problem3,Settings,Proof) ->
      ( Conj\=[] -> Result='Theorem' ; Result='Unsatisfiable' ) ;
      ( Conj\=[] -> Result='Non-Theorem' ; Result='Satisfiable' )
    ),
    bmatrix(Problem2,Settings,Matrix),
    output_result(File,Matrix,Proof,Result,Conj).

% print status and connection proof

output_result(File,Matrix,Proof,Result,Conj) :-
    ( Conj\=[] -> Art=' is a ' ; Art=' is ' ), nl,
    ( logic(Logic) -> true ), print(File),
    print(Art), print(Logic), print(' '), print(Result), nl,
    ( var(Proof) ; Logic\=intu ) -> true ;
      print('Start of proof'),
      ( Result='Theorem' -> Out=' for ' ; Out=' for negated ' ),
      print(Out), print(File), nl, nanocopi_proof(Matrix,Proof),
      print('End of proof'), print(Out), print(File), nl.
