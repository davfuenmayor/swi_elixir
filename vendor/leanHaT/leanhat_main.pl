%% File: leanhat_main.pl  -  Version: 1.0  -  Date: 1 April 2025
%%
%% Purpose: Call the leanHaT core prover for a given formula
%%
%% Authors: Jens Otten
%% Web:     www.leancop.de/leanhat/
%%
%% Usage:   leanhat_main(X,S,R). % proves formula in file X with
%%                               %  settings S and returns result R
%%
%% Copyright: (c) 2017-2025 by Jens Otten
%% License:   GNU General Public License

:- assert(prolog(swi)).  % Prolog dialect (eclipse/swi)
:- dynamic(axiom_path/1).

% execute predicates specific to Prolog dialect

:- \+ prolog(eclipse) -> true ;
   nodbgcomp,  % switch off debugging mode
   set_flag(print_depth,10000),  % set print depth
   set_flag(variable_names,off),  % print internal variable names
   ( getenv('TPTP',Path) -> Path1=Path ; Path1='' ),
   retract_all(axiom_path(_)), assert(axiom_path(Path1)),
   [leanhat].  % load leanHaT core prover

:- prolog(eclipse) -> true ;
   set_prolog_flag(print_write_options,[quoted(false)]),
   set_prolog_flag(optimise,true),  % optimise compilation
   ( getenv('TPTP',Path) -> Path1=Path ; Path1='' ),
   retractall(axiom_path(_)), assert(axiom_path(Path1)),
   [leanhat_swi].  % load leanHaT core prover

% load additional leanHaT components

:- [nanocop_tptp2].  % load module to support TPTP syntax

%%% call leanHaT core prover

leanhat_main(File,_,Result) :-
    axiom_path(AxPath), ( AxPath='' -> AxDir='' ;
    name(AxPath,AxL), append(AxL,[47],DirL), name(AxDir,DirL) ),
    ( leancop_tptp2(File,AxDir,[_],F,Conj) ->
      Problem=F ; [File], f(Problem), Conj=non_empty ),
    ( Conj\=[] -> Problem1=Problem ; Problem1=(~Problem) ),
    leancop_equal(Problem1,Problem2),
    ( prove(Problem2) ->
      ( Conj\=[] -> Result='Theorem' ; Result='Unsatisfiable' ) ;
      ( Conj\=[] -> Result='Non-Theorem' ; Result='Satisfiable' )
    ),
    output_result(File,Result,Conj).

% print status and connection proof

output_result(File,Result,Conj) :-
    ( Conj\=[] -> Art=' is an HT ' ; Art=' is HT ' ), nl,
    print(File),  print(Art), print(Result), nl.
