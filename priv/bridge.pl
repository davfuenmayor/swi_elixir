:- module(swi_bridge, [rpc/2, main/0, read_goal/4]).
:- use_module(library(http/json)).
:- use_module(library(time)).
:- use_module(library(readutil)).
:- thread_local cursor/1, loading/0, loading_error/1.
:- multifile user:message_hook/3.

% SWI reports some compilation errors as messages while load_files succeeds.
% Capture these only during this session's load and return the original error.
user:message_hook(Error, Level, _) :-
    swi_bridge:loading, swi_bridge:load_failure(Level, Error),
    assertz(swi_bridge:loading_error(Error)).
load_failure(error, _).
load_failure(warning, initialization_failure(_, _)).
load_failure(warning, goal_failed(directive, _)).

% One cursor per session. Prolog engines retain the choice points between pulls.
rpc(Request, Response) :-
    catch((atom_json_dict(Request, Dict, []), dispatch(Dict, Reply),
           atom_json_dict(Response, Reply, [as(atom), width(0)])), Error,
          (catch(close_cursor, _, true), error_reply(Error, Failure),
           atom_json_dict(Response, Failure, [as(atom), width(0)]))).

error_reply(time_limit_exceeded, _{status:timeout}) :- !.
error_reply(Error, _{status:error, error:Text}) :-
    term_string(Error, Text, [quoted(true), cycles(true)]).

dispatch(D, _{status:ready, protocol:1}) :- D.op == "hello", !,
    call_with_time_limit(D.timeout, true).
dispatch(D, _{status:ok}) :- D.op == "open", !,
    close_cursor,
    read_goal(D.goal, user, Goal, Bindings),
    engine_create(_, solutions(user:Goal, Bindings), Engine), assertz(cursor(Engine)).
dispatch(D, Reply) :- D.op == "next", !,
    ( cursor(Engine) ->
      (engine_post(Engine, D.timeout, Bindings) ->
       encode_bindings(Bindings, Encoded), Reply=_{status:solution, bindings:Encoded}
      ; destroy_cursor, Reply=_{status:done})
    ; Reply=_{status:done} ).
dispatch(D, _{status:ok}) :- D.op == "close", !, close_cursor.
dispatch(D, _{status:ok}) :- D.op == "load", !,
    (call_with_time_limit(D.timeout, consult_file(D.path)) -> true
    ; throw(error(load_failed(D.path), _))).
dispatch(D, _) :- throw(error(domain_error(operation, D), _)).

% read_term/3 checks the whole input. Retry EOF-terminated goals with a final
% period, preserving the text API's optional-period convention and comments.
read_goal(Text, Module, Goal, Bindings) :-
    catch(read_goal_stream(Text, Module, Goal, Bindings),
          error(syntax_error(end_of_file), _),
          (string_concat(Text, "\n.", Terminated),
           read_goal_stream(Terminated, Module, Goal, Bindings))).
read_goal_stream(Text, Module, Goal, Bindings) :-
    setup_call_cleanup(open_string(Text, Stream),
      (read_term(Stream, Goal, [variable_names(Bindings), module(Module)]),
       read_term(Stream, End, [module(Module)]),
       (End == end_of_file, stream_property(Stream, end_of_stream(at)) -> true
       ; throw(error(syntax_error(trailing_input), _)))),
      close(Stream)).

consult_file(Path) :-
    setup_call_cleanup(
      (retractall(loading_error(_)), asserta(loading)),
      (user:load_files(Path, [if(true)]),
       (loading_error(Error) -> throw(Error) ; true)),
      (retractall(loading), retractall(loading_error(_)))).

% Keep the timer inside the query engine: an alarm in its parent cannot
% interrupt a child engine. Suspend it while the consumer processes an answer.
solutions(Goal, Bindings) :-
    engine_fetch(Seconds),
    (Seconds == close -> true
    ; setup_call_cleanup(
        alarm(Seconds, throw(time_limit_exceeded), Alarm, [remove(false)]),
        answers(Goal, Bindings, Alarm), remove_alarm(Alarm))).

answers(Goal, Bindings, Alarm) :-
    call(Goal), uninstall_alarm(Alarm), engine_yield(Bindings),
    engine_fetch(Command),
    (Command == close -> ! ; install_alarm(Alarm, Command), fail).

% Resume suspended search so cleanup exceptions can reach the caller.
% Forced engine destruction alone discards exceptions from cleanup handlers.
close_cursor :-
    (retract(cursor(E)) ->
      setup_call_cleanup(true, (engine_post(E, close, _) -> true ; true), engine_destroy(E))
    ; true).
destroy_cursor :- (retract(cursor(E)) -> engine_destroy(E) ; true).

encode_bindings(Bindings, Dict) :-
    term_variables(Bindings, Variables),
    maplist(binding(Variables), Bindings, Pairs), dict_pairs(Dict, bindings, Pairs).
binding(Vars, Name=Term, Name-Value) :-
    (acyclic_term(Term) -> encode(Vars, Term, Value)
    ; term_string(Term, Text, [quoted(true), cycles(true)]), Value=_{t:prolog,v:Text}).

encode(Vars, Term, _{t:var,v:N}) :- var(Term), !, var_index(Term, Vars, 0, N).
encode(_, Term, _{t:atom,v:Name}) :- atom(Term), Term \== [], !, atom_string(Term, Name).
encode(_, [], _{t:list,v:[]}) :- !.
encode(_, Term, _{t:number,v:Term}) :- integer(Term), !.
encode(_, Term, _{t:number,v:Term}) :-
    float(Term), float_class(Term, Class), \+ memberchk(Class, [infinite,nan]), !.
encode(_, Term, _{t:string,v:Term}) :- string(Term), !.
encode(Vars, Term, _{t:list,v:Values}) :- is_list(Term), !, maplist(encode(Vars), Term, Values).
encode(Vars, [Head|Tail], _{t:cons,v:[H,T]}) :- !, encode(Vars,Head,H), encode(Vars,Tail,T).
encode(Vars, Term, _{t:compound,f:Name,v:Values}) :-
    compound(Term), \+ is_dict(Term), !,
    compound_name_arguments(Term, Functor, Args), atom_string(Functor, Name),
    maplist(encode(Vars), Args, Values).
encode(_, Term, _{t:prolog,v:Text}) :- term_string(Term, Text, [quoted(true)]).
var_index(Term, [V|_], N, N) :- Term == V, !.
var_index(Term, [_|Vs], N, Index) :- N1 is N+1, var_index(Term, Vs, N1, Index).

% The main thread keeps reading even while the worker searches. EOF means
% the BEAM Port owner vanished: kill this disposable runtime immediately.
main :-
    use_module(library(process)),
    current_output(Protocol),
    set_prolog_IO(user_input, user_error, user_error),
    thread_create(worker(Protocol), Worker, [detached(true)]),
    read_requests(Worker).
read_requests(Worker) :-
    read_line_to_string(user_input, Line),
    (Line == end_of_file -> kill_runtime
    ; thread_send_message(Worker, Line), read_requests(Worker)).
kill_runtime :-
    current_prolog_flag(pid, Pid),
    (current_prolog_flag(windows, true) ->
        getenv('SystemRoot', Root),
        directory_file_path(Root, 'System32/taskkill.exe', Taskkill),
        process_create(Taskkill, ['/F', '/PID', Pid],
                       [stdin(null), stdout(null), stderr(null), detached(true)])
    ; process_kill(Pid, kill)).
worker(Protocol) :-
    catch(loop(Protocol), Error, (print_message(error, Error), halt(1))).
loop(Protocol) :-
    thread_get_message(Line),
    atom_string(Request, Line), rpc(Request, Reply),
    format(Protocol, '~a~n', [Reply]), flush_output(Protocol), loop(Protocol).
