%% @doc Supervisor for file processes, these processes cache and maintain file information for
%% other file services.  They can also resize, combine files and compress files.

%% Copyright 2013-2014 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(z_file_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-export([
    ensure_file/4,
    pause_file/4,
    refresh/0
    ]).

-define(SERVER, ?MODULE).

ensure_file(Path, Root, OptFilters, Context) ->
    {ok, Pid} = ensure_file_process(locate, Path, Root, OptFilters, Context),
    lookup_file(Pid).

pause_file(Path, Root, OptFilters, Context) ->
    {ok, Pid} = ensure_file_process(paused, Path, Root, OptFilters, Context),
    z_file_entry:pause(Pid).

ensure_file_process(InitialState, Path, Root, OptFilters, Context) ->
    case z_file_entry:where(Path, Context) of
        Pid when is_pid(Pid) ->
            {ok, Pid};
        undefined ->
            case supervisor:start_child(?SERVER, [InitialState, Path, Root, OptFilters, Context]) of
                {ok, Pid} ->
                    {ok, Pid};
                {error,{already_started, Pid}} ->
                    {ok, Pid}
            end
    end.

lookup_file(Pid) ->
    z_file_entry:lookup(Pid).


%% @doc Flush all cached file entries, needed if some missing files are now
%%      present.
-spec refresh() -> ok.
refresh() ->
    Children = supervisor:which_children(?SERVER),
    lists:foreach(
        fun
            ({_Id, Child, worker, _Modules}) ->
                z_file_entry:force_stale(Child);
            (_) ->
                ok
        end,
        Children).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    Element = {z_file_entry, {z_file_entry, start_link, []},
               temporary, brutal_kill, worker, [z_file_entry]},
    Children = [Element],
    RestartStrategy = {simple_one_for_one, 0, 1},
    {ok, {RestartStrategy, Children}}.

