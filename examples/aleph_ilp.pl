% Project-authored orchestration/evaluation for the upstream Aleph examples.
:- module(aleph_ilp, [learn_task/8, learn_task/9]).
:- use_module('../vendor/aleph/aleph.pl').
:- use_module(ilp_support).

lesson(trains, aleph_trains, eastbound(_), 'aleph_trains.pl').
lesson(membership, aleph_membership, mem(_,_), 'aleph_membership.pl').
tests(trains,
 [eastbound(probe_yes)-true, eastbound(probe_long)-false,
  eastbound(probe_open)-false, eastbound(probe_split)-false]).
tests(membership,
 [mem(z,[a,b,c,d,e,z])-true, mem(z,[a,b,c])-false,
  mem(a,[])-false, mem(a,[a,a])-true]).

% Re-read the task for each experiment: Aleph consumes examples and updates its
% background during induction. Serialize reconsult/search in the shared NIF VM.
learn_task(Task, Length, ProgramText, Rows, Clauses, BottomText, ReducedText, Trace) :-
    lesson(Task, _, _, File),
    source_file(aleph_ilp:learn_task(_,_,_,_,_,_,_,_), Source),
    file_directory_name(Source, Directory), directory_file_path(Directory, File, Path),
    learn_task(Task, Length, ProgramText, Rows, Clauses, BottomText, ReducedText, Trace, Path).

learn_task(Task, Length, ProgramText, Rows, Clauses, BottomText, ReducedText, Trace, Path) :-
    must_be(integer, Length), between(1,6,Length),
    lesson(Task, Module, Target, _),
    with_mutex(aleph_ilp,
      setup_call_cleanup(
        load_task_source(Module, Path),
        with_output_to(string(Trace),
        (Module:aleph_set(clauselength, Length),
         Module:aleph_set(noise, 0), Module:aleph_set(nodes, 5000),
         once(Module:sat(1)), Module:bottom(Bottom), program_text([Bottom], BottomText),
         once(Module:reduce(Reduced)), program_text([Reduced], ReducedText),
         once(Module:induce(Program)),
         length(Program, Clauses), program_text(Program, ProgramText),
         findall(P, Module:example(_,pos,P), Pos),
         findall(N, Module:example(_,neg,N), Neg), tests(Task, Tests),
         evaluate(Module, Pos, Neg, Tests, Rows))),
        cleanup(Module, Target))).

load_task_source(Module, Path) :-
    forall((source_file(Module:_, Loaded), file_base_name(Loaded, Name),
            memberchk(Name, ['aleph_trains.pl','aleph_membership.pl']),
            Loaded \== Path), unload_file(Loaded)),
    load_files(Path, [if(true)]).

cleanup(Module, Target) :-
    retractall(Module:Target),
    % Aleph initializes zero-arity command shims with assert/1. Reconsult does
    % not replace those clauses; remove our private modules' generated shims.
    forall((predicate_property(Module:Head, dynamic), functor(Head,_,0),
            \+ predicate_property(Module:Head, imported_from(_)),
            clause(Module:Head, _, Ref), \+ clause_property(Ref, file(_))),
           erase(Ref)).
