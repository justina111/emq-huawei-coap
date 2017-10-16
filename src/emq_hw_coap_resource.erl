%%--------------------------------------------------------------------
%% Copyright (c) 2016-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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
%%--------------------------------------------------------------------

-module(emq_hw_coap_resource).

-behaviour(lwm2m_coap_resource).

-include("emq_hw_coap.hrl").

-include_lib("lwm2m_coap/include/coap.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-export([coap_discover/2, coap_get/5, coap_post/4, coap_put/4, coap_delete/3,
         coap_observe/5, coap_unobserve/1, handle_info/2, coap_ack/2]).

-ifdef(TEST).
-export([topic/1]).
-endif.

-define(MQTT_PREFIX, [<<"mqtt">>]).
-define(NB_PREFIX, [<<"t">>]).

-define(LOG(Level, Format, Args),
    lager:Level("CoAP-RES: " ++ Format, Args)).

% resource operations
coap_discover(_Prefix, _Args) ->
    [{absolute, "mqtt", []}].

coap_get(ChId, ?MQTT_PREFIX, Name, Query, _Content) ->
    ?LOG(debug, "coap_get() ChId=~p, Name=~p, Query=~p~n", [ChId, Name, Query]),
    #coap_mqtt_auth{clientid = Clientid, username = Usr, password = Passwd} = get_auth(Query),
    case emq_hw_coap_mqtt_adapter:client_pid(Clientid, Usr, Passwd, ChId) of
        {ok, Pid} ->
            put(mqtt_client_pid, Pid),
            emq_hw_coap_mqtt_adapter:keepalive(Pid),
            #coap_content{};
        {error, auth_failure} ->
            put(mqtt_client_pid, undefined),
            {error, uauthorized};
        {error, bad_request} ->
            put(mqtt_client_pid, undefined),
            {error, bad_request};
        {error, _Other} ->
            put(mqtt_client_pid, undefined),
            {error, internal_server_error}
    end;

coap_get(ChId, ?NB_PREFIX, Name, Query, _Content) ->
    ?LOG(debug, "coap_get() Name=~p, Query=~p~n", [Name, Query]),
    case Name of
        [<<"r">>] ->
            #coap_mqtt_auth{clientid = Clientid, username = Usr, password = Passwd} = get_auth(Query),
            ?LOG(debug, "Clientid =~p, username=~p, password=~p~n", [Clientid, Usr, Passwd]),
            case emq_hw_coap_mqtt_adapter:client_pid(list_to_binary("nbiot_"++binary_to_list(Clientid)), Usr, Passwd, ChId) of
                {ok, Pid} ->
                    put(mqtt_client_pid, Pid),
                    emq_hw_coap_mqtt_adapter:keepalive(Pid),
                    ?LOG(debug, "coap_get() will send observe_nb_device~n", []),
                    %erlang:send_after(1000, Pid, {observe_nb_device, self()}),
                    Pid ! {observe_nb_device, self()},
                    #coap_content{};
                {error, auth_failure} ->
                    put(mqtt_client_pid, undefined),
                    {error, uauthorized};
                {error, bad_request} ->
                    put(mqtt_client_pid, undefined),
                    {error, bad_request};
                {error, _Other} ->
                    put(mqtt_client_pid, undefined),
                    {error, internal_server_error}
            end;
        [<<"d">>] ->
            ?LOG(debug, "coap_get() receives Name=~p, Query=~p~n", [Name, Query]),
            #coap_content{};
        _else     ->
            ?LOG(debug, "coap_get() receives unknown Name=~p, Query=~p~n", [Name, Query]),
            {error, bad_request}
    end;


coap_get(ChId, Prefix, Name, Query, _Content) ->
    ?LOG(error, "ignore bad put request ChId=~p, Prefix=~p, Name=~p, Query=~p", [ChId, Prefix, Name, Query]),
    {error, bad_request}.

coap_post(ChId = {{A,B,C,D}, Port}, ?NB_PREFIX, [Topic], Content = #coap_content{}) ->
    ?LOG(debug, "post message, ChId =~p, Topic=~p, Content=~p~n", [ChId, Topic, Content]),
    %Pid = get(mqtt_client_pid),
    %emq_coap_mqtt_adapter:publish(Pid, topic(Topic), Payload),
    %IPBin = integer_to_list(A)++"."++integer_to_list(B)++"."++integer_to_list(C)++"."++integer_to_list(D),
    %Uri = "coap://"++IPBin++"/t/d",
    %?LOG(debug, "observe Uri=~p~n", [Uri]),
    %spawn(coap_observer:observe(Uri)),
    {ok, valid, Content};

coap_post(_ChId, _Prefix, _Name, _Content) ->
    {error, method_not_allowed}.

coap_put(_ChId, ?MQTT_PREFIX, [Topic], #coap_content{payload = Payload}) ->
    ?LOG(debug, "put message, Topic=~p, Payload=~p~n", [Topic, Payload]),
    Pid = get(mqtt_client_pid),
    emq_hw_coap_mqtt_adapter:publish(Pid, topic(Topic), Payload),
    ok;
coap_put(_ChId, ?NB_PREFIX, [Topic], #coap_content{payload = Payload}) ->
    ?LOG(debug, "put message, Topic=~p, Payload=~p~n", [Topic, Payload]),
    Pid = get(mqtt_client_pid),
    emq_hw_coap_mqtt_adapter:publish(Pid, topic(Topic), Payload),
    ok;
coap_put(_ChId, Prefix, Name, Content) ->
    ?LOG(error, "put has error, Prefix=~p, Name=~p, Content=~p", [Prefix, Name, Content]),
    {error, bad_request}.

coap_delete(_ChId, _Prefix, _Name) ->
    {error, method_not_allowed}.

coap_observe(ChId, ?MQTT_PREFIX, [Topic], Ack, Content) ->
    TrueTopic = topic(Topic),
    ?LOG(debug, "observe Topic=~p, Ack=~p", [TrueTopic, Ack]),
    Pid = get(mqtt_client_pid),
    emq_hw_coap_mqtt_adapter:subscribe(Pid, TrueTopic),
    {ok, {state, ChId, ?MQTT_PREFIX, [TrueTopic]}, content, Content};
coap_observe(ChId, ?NB_PREFIX, [Topic], Ack, Content) ->
    TrueTopic = topic(Topic),
    ?LOG(debug, "observe Topic=~p, Ack=~p", [TrueTopic, Ack]),
    Pid = get(mqtt_client_pid),
    emq_hw_coap_mqtt_adapter:subscribe(Pid, TrueTopic),
    {ok, {state, ChId, ?MQTT_PREFIX, [TrueTopic]}, content, Content};
coap_observe(ChId, Prefix, Name, Ack, _Content) ->
    ?LOG(error, "unknown observe request ChId=~p, Prefix=~p, Name=~p, Ack=~p", [ChId, Prefix, Name, Ack]),
    {error, bad_request}.

coap_unobserve({state, _ChId, ?MQTT_PREFIX, [Topic]}) ->
    ?LOG(debug, "unobserve ~p", [Topic]),
    Pid = get(mqtt_client_pid),
    emq_hw_coap_mqtt_adapter:unsubscribe(Pid, Topic),
    ok;
coap_unobserve({state, ChId, Prefix, Name}) ->
    ?LOG(error, "ignore unknown unobserve request ChId=~p, Prefix=~p, Name=~p", [ChId, Prefix, Name]),
    ok.

handle_info({dispatch, Topic, Payload}, State) ->
    ?LOG(debug, "dispatch Topic=~p, Payload=~p", [Topic, Payload]),
    {notify, [], #coap_content{format = <<"application/octet-stream">>, payload = Payload}, State};

handle_info({dispatch_observe, CoapRequest, Ref}, _State) ->
    ?LOG(debug, "dispatch_observe CoapRequest=~p, Ref=~p", [CoapRequest, Ref]),
    {send_request, CoapRequest, Ref};

handle_info({coap_response, _ChId, _Channel, Ref, Msg=#coap_message{type = _Type, method = _Method, options = _Options}}, ObState) ->
    ?LOG(debug, "receive coap response from device ~p, Ref = ~p~n", [Msg, Ref]),
    {noreply, ObState};

handle_info(Message, State) ->
    ?LOG(error, "Unknown Message ~p", [Message]),
    {noreply, State}.

coap_ack(_Ref, State) -> {ok, State}.

get_auth(Query) ->
    get_auth(Query, #coap_mqtt_auth{}).

get_auth([], Auth=#coap_mqtt_auth{}) ->
    Auth;
get_auth([<<$c, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{clientid = Rest});
get_auth([<<$u, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{username = Rest});
get_auth([<<$p, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{password = Rest});
get_auth([<<$e, $p, $=, Rest/binary>>|T], Auth=#coap_mqtt_auth{}) ->
    get_auth(T, Auth#coap_mqtt_auth{clientid = Rest, username = <<"nbuser">>, password = <<"nbpass">>});
get_auth([Param|T], Auth=#coap_mqtt_auth{}) ->
    ?LOG(error, "ignore unknown parameter ~p", [Param]),
    get_auth(T, Auth).

nb_get_auth() ->
    #coap_mqtt_auth{clientid = <<"nbclient">>, username = <<"nbuser">>, password = <<"nbpass">>}.

topic(TopicBinary) ->
    %% RFC 7252 section 6.4. Decomposing URIs into Options
    %%     Note that these rules completely resolve any percent-encoding.
    %% That is to say: URI may have percent-encoding. But coap options has no percent-encoding at all.
    TopicBinary.
