%% 
%% Basic implementation of the WebSocket API:
%% http://dev.w3.org/html5/websockets/
%% However, it's not completely compliant with the WebSocket spec.
%% Specifically it doesn't handle the case where 'length' is included
%% in the TCP packet, SSL is not supported, and you don't pass a 'ws://type url to it.
%%
%% It also defines a behaviour to implement for client implementations.
%% @author Dave Bryson [http://weblog.miceda.org]
%%
-module(ti_websocket_client).

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, 
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% Ready States
-define(CONNECTING, 0).
-define(OPEN, 1).
-define(CLOSED, 2).

%% Behaviour definition
%-export([behaviour_info/1]).

%behaviour_info(callbacks) ->
%    [{onmessage, 1}, {onopen, 0}, {onclose, 0}, {close, 0}, {send, 1}];
%behaviour_info(_) ->
%    undefined.

-record(state, {socket, readystate=undefined, headers=[], pid=undefined, wspid=undefined}).

start_link(Hostname, Port) ->
    gen_server:start_link(?MODULE, [Hostname, Port], []).

init([Hostname, Port]) ->
    process_flag(trap_exit, true),
    case gen_tcp:connect(Hostname, Port, [binary, {packet, 0}, {active,true}]) of
        {ok, Socket} ->
            Request = "GET / HTTP/1.1\r\nUpgrade: WebSocket\r\nConnection: Upgrade\r\n" ++
                          "Host: " ++ Hostname ++ "\r\n" ++ "Origin: http://" ++ Hostname ++ "/\r\n\r\n",
            case gen_tcp:send(Socket, Request) of
                ok ->
                    inet:setopts(Socket, [{packet, http}]),    
                    Pid = self(),
                    WSPid = spawn(fun() -> msg2websocket_process(Pid, Socket) end),
                    {ok, #state{socket=Socket, pid=Pid, wspid=WSPid}};
                {error, Reason} ->
                    ti_common:logerror("WebSocket gen_tcp:send initial request fails : ~p~n", [Reason]),
                    {stop, Reason}
            end;
        {error, Reason} ->
            ti_common:logerror("WebSocket gen_tcp:connect fails : ~p~n", [Reason]),
            {stop, Reason}
    end.

handle_call(_Request, _From, State) ->
    {noreply, ok, State}.

handle_cast(_Msg, State) ->    
    {noreply, State}. 

%% Start handshake
handle_info({http, Socket, {http_response, {1, 1}, 101, "Web Socket Protocol Handshake"}}, State) ->
    NewState = State#state{readystate=?CONNECTING, socket=Socket},
    {noreply, NewState};
%% Extract the headers
handle_info({http, Socket, {http_header, _, Name, _, Value}},State) ->
    case State#state.readystate of
    ?CONNECTING ->
        H = [{Name,Value} | State#state.headers],
        State1 = State#state{headers=H, socket=Socket},
        {noreply, State1};
    undefined ->
        %% Bad state should have received response first
        {stop, error, State}
    end;
%% Once we have all the headers check for the 'Upgrade' flag 
handle_info({http, Socket, http_eoh}, State) ->
    %% Validate headers, set state, change packet type back to raw
    case State#state.readystate of
    ?CONNECTING ->
         Headers = State#state.headers,
         case proplists:get_value('Upgrade', Headers) of
         "WebSocket" ->
             inet:setopts(Socket, [{packet, raw}]),
             NewState = State#state{readystate=?OPEN, socket=Socket},
             {noreply, NewState};
         _Any  ->
             {stop, error, State}
         end;
    undefined ->
        %% Bad state should have received response first
        {stop, error, State}
    end;
%% Handshake complete, handle packets
handle_info({tcp, _Socket, Data}, State) ->
    case State#state.readystate of
    ?OPEN ->
        D = unframe(binary_to_list(Data)),
        {noreply, State};
    _Any ->
        {stop, error, State}
    end;
handle_info({tcp_closed, _Socket}, State) ->
    {stop, normal, State};
handle_info({tcp_error, _Socket, _Reason},State) ->
    {stop,tcp_error, State};
handle_info({'EXIT', _Pid, _Reason},State) ->
    {noreply, State}.

terminate(Reason, _State) ->
    error_logger:info_msg("Terminated ~p~n", [Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

unframe([0|T]) -> unframe1(T).
unframe1([255]) -> [];
unframe1([H|T]) -> [H|unframe1(T)].

msg2websocket_process(Pid, Sock) ->
    ok.


    
