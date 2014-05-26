%%%
%%%
%%%

-module(msapp).

-behaviour(application).

-include("header.hrl").

%-export([start_client_vdr/1]).

-export([start/2, stop/1]).

%host: 42.96.146.34
%user: optimus
%passwd: opt123450
%port:3306
%dbname: gps_database

%cd /home/optimus/innovbackend/gateway/src
%make
%cd ../ebin
%erl -P 655350 -Q 655350
%application:start(sasl).
%application:start(msapp).

%%%
%%% rawdisplay  : 0 -> error_logger
%%%               1 -> terminal
%%% display     : 1 -> no log
%%%               1 -> log
%%%
start(StartType, StartArgs) ->
	Len = length(StartArgs),
	case Len of
		13 ->
			[PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path] = StartArgs,
			startserver(StartType, [PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, "58.246.201.138:8081", 0]);
		14 ->
			[PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, HttpGps] = StartArgs,
			case HttpGps of
				1 ->
					startserver(StartType, [PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, "58.246.201.138:8081", 1]);
				0 ->
					startserver(StartType, [PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, "58.246.201.138:8081", 0]);
				_ ->
					startserver(StartType, [PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, HttpGps, 1])
			end;
		_ ->
			common:logerror("Parameter count error : ~p", [Len])
	end.
	
startserver(StartType, StartArgs) ->
    [PortVDR, PortMon, PortMP, WS, PortWS, DB, DBName, DBUid, DBPwd, MaxR, MaxT, Mode, Path, HttpGpsServer, HttpGpsState] = StartArgs,
    AppPid = self(),
    ets:new(msgservertable,[set,public,named_table,{keypos,1},{read_concurrency,true},{write_concurrency,true}]),
    ets:insert(msgservertable, {portvdr, PortVDR}),
    ets:insert(msgservertable, {portmon, PortMon}),
    ets:insert(msgservertable, {portmp, PortMP}),
    ets:insert(msgservertable, {ws, WS}),
    ets:insert(msgservertable, {portws, PortWS}),
    ets:insert(msgservertable, {db, DB}),
    ets:insert(msgservertable, {dbname, DBName}),
    ets:insert(msgservertable, {dbuid, DBUid}),
    ets:insert(msgservertable, {dbpwd, DBPwd}),
    ets:insert(msgservertable, {maxr, MaxR}),
    ets:insert(msgservertable, {maxt, MaxT}),
    ets:insert(msgservertable, {mode, Mode}),
    ets:insert(msgservertable, {path, Path}),
	ets:insert(msgservertable, {httpgpsserver, HttpGpsServer}),
    ets:insert(msgservertable, {dbpid, undefined}),
    ets:insert(msgservertable, {wspid, undefined}),
    ets:insert(msgservertable, {linkpid, undefined}),
	ets:insert(msgservertable, {dboperationpid, undefined}),
	ets:insert(msgservertable, {dbmaintainpid, undefined}),
	if
		Mode == 2 orelse Mode == 1 ->
			ets:insert(msgservertable, {dbstate, true});
		true ->
			ets:insert(msgservertable, {dbstate, false})
	end,
    ets:insert(msgservertable, {apppid, AppPid}),
    ets:insert(msgservertable, {dblog, []}),
    ets:insert(msgservertable, {wslog, []}),
    common:loginfo("StartType : ~p", [StartType]),
    common:loginfo("StartArgs : ~p", [StartArgs]),
    ets:new(alarmtable,[bag,public,named_table,{keypos,#alarmitem.vehicleid},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(vdrdbtable,[ordered_set,public,named_table,{keypos,#vdrdbitem.authencode},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(vdrtable,[ordered_set,public,named_table,{keypos,#vdritem.socket},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(mantable,[set,public,named_table,{keypos,#manitem.socket},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(usertable,[set,public,named_table,{keypos,#user.id},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(drivertable,[set,public,named_table,{keypos,#driverinfo.driverid},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(lastpostable,[set,public,named_table,{keypos,#lastposinfo.vehicleid},{read_concurrency,true},{write_concurrency,true}]),
    ets:new(montable,[set,public,named_table,{keypos,#monitem.socket},{read_concurrency,true},{write_concurrency,true}]),
    common:loginfo("Tables are initialized."),
	case file:make_dir(Path ++ "/media") of
		ok ->
			common:loginfo("Successfully create directory media");
		{error, DirError0} ->
			common:logerror("Cannot create directory media : ~p", [DirError0])
	end,
	case file:make_dir(Path ++ "/upgrade") of
		ok ->
			common:loginfo("Successfully create directory upgrade");
		{error, DirError1} ->
			common:logerror("Cannot create directory upgrade : ~p", [DirError1])
	end,
    case supervisor:start_link(mssup, []) of
        {ok, SupPid} ->
            ets:insert(msgservertable, {suppid, SupPid}),
            common:loginfo("Message server starts"),
            common:loginfo("Application PID is ~p", [AppPid]),
            common:loginfo("Supervisor PID : ~p", [SupPid]),
            case receive_db_ws_init_msg(false, false, 0, Mode) of
                ok ->
                    mysql:utf8connect(conn, DB, undefined, DBUid, DBPwd, DBName, true),
					if
						Mode == 2 ->
		                    LinkPid = spawn(fun() -> connection_info_process(0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0,
																			 0) end),
		                    WSPid = spawn(fun() -> wsock_client:wsock_client_process(0, 0) end),
		                    DBPid = spawn(fun() -> mysql:mysql_process(0, 0, [<<"">>, <<"">>, []], 0, [<<"">>, <<"">>, []], 0, [], 0, [<<"">>, <<"">>, []], 0, LinkPid) end),
		                    DBTablePid = spawn(fun() -> db_table_deamon() end),
		                    CCPid = spawn(fun() -> code_convertor_process() end),
		                    VdrTablePid = spawn(fun() -> vdrtable_insert_delete_process() end),
		                    DriverTablePid = spawn(fun() -> drivertable_insert_delete_process() end),
		                    LastPosTablePid = spawn(fun() -> lastpostable_insert_delete_process() end),
							DBOperationPid = spawn(fun() -> db_data_operation_process(DBPid) end),
							MysqlActivePid = spawn(fun() -> mysql_active_process(DBPid) end),
							HttpGpsPid = spawn(fun() -> http_gps_deamon(HttpGpsServer, uninit, 0, 0, 0, 0) end),
							%DBMaintainPid = spawn(fun() -> db_data_maintain_process(DBPid, DBOperationPid, Mode) end),
		                    ets:insert(msgservertable, {dbpid, DBPid}),
		                    ets:insert(msgservertable, {wspid, WSPid}),
		                    ets:insert(msgservertable, {linkpid, LinkPid}),
		                    ets:insert(msgservertable, {dbtablepid, DBTablePid}),
		                    ets:insert(msgservertable, {ccpid, CCPid}),
		                    ets:insert(msgservertable, {vdrtablepid, VdrTablePid}),
		                    ets:insert(msgservertable, {drivertablepid, DriverTablePid}),
		                    ets:insert(msgservertable, {lastpostablepid, LastPosTablePid}),
							ets:insert(msgservertable, {dboperationpid, DBOperationPid}),
							ets:insert(msgservertable, {mysqlactivepid, MysqlActivePid}),
							ets:insert(msgservertable, {httpgpspid, HttpGpsPid}),
		                    %ets:insert(msgservertable, {dbmaintainpid, VdrTablePid}),
		                    common:loginfo("WS client process PID is ~p", [WSPid]),
		                    common:loginfo("DB client process PID is ~p", [DBPid]),
		                    common:loginfo("DB table deamon process PID is ~p", [DBTablePid]),
		                    common:loginfo("Code convertor process PID is ~p", [CCPid]),
		                    common:loginfo("VDR table processor process PID is ~p", [VdrTablePid]),
		                    common:loginfo("Driver table processor process PID is ~p", [DriverTablePid]),
		                    common:loginfo("Last pos table processor process PID is ~p", [LastPosTablePid]),
							common:loginfo("DB operation process PID is ~p", [DBOperationPid]),
							common:loginfo("Mysql active process PID is ~p", [MysqlActivePid]),
							common:loginfo("HTTP GPS process PID is ~p", [HttpGpsPid]),
							%common:loginfo("DB miantain process PID is ~p", [DBMaintainPid]),

							case HttpGpsState of
								1 ->
									HttpGpsPid ! init;
								_ ->
									ok
							end,
							%HttpGpsPid ! {self(), normal, [116.283016, 39.959856]},
							%HttpGpsPid ! {self(), abnormal, [116.283016, 39.959856]},
		                    
				            common:loginfo("DB coding setting"),
							DBPid ! {AppPid, conn, <<"set names 'utf8'">>},
				            receive
				                {AppPid, _} ->
									common:loginfo("DB coding setting returns"),
									case init_vdrdbtable(AppPid, DBPid) of
										{error, ErrorMsg} ->
											{error, ErrorMsg};
										ok ->
											case init_lastpostable(AppPid, DBPid) of
												{error, ErrorMsg} ->
													{error, ErrorMsg};
												ok ->
													case init_alarmtable(AppPid, DBPid) of
														{error, ErrorMsg1} ->
															{error, ErrorMsg1};
														ok ->
															case init_drivertable(AppPid, DBPid) of
																{error, ErrorMsg2} ->
																	{error, ErrorMsg2};
																ok ->
												                    CCPid ! {AppPid, create},
												                    receive
												                        created ->
												                            common:loginfo("Code convertor table is created"),
												                            {ok, AppPid}
												                        after ?TIMEOUT_CC_INIT_PROCESS ->
												                            {error, "ERROR : code convertor table is timeout"}
																	end
															end
													end
											end
									end
							after
								?DB_RESP_TIMEOUT ->
									{error, "ERROR : init db coding is timeout"}
							end;
						true ->
		                    LinkPid = spawn(fun() -> connection_info_process(0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0, 
																			 0, 0, 0, 0, 0,
																			 0) end),
		                    DBPid = spawn(fun() -> mysql:mysql_process(0, 0, [<<"">>, <<"">>, []], 0, [<<"">>, <<"">>, []], 0, [], 0, [<<"">>, <<"">>, []], 0, LinkPid) end),
		                    DBTablePid = spawn(fun() -> db_table_deamon() end),
		                    CCPid = spawn(fun() -> code_convertor_process() end),
		                    VdrTablePid = spawn(fun() -> vdrtable_insert_delete_process() end),
		                    DriverTablePid = spawn(fun() -> drivertable_insert_delete_process() end),
		                    LastPosTablePid = spawn(fun() -> lastpostable_insert_delete_process() end),
							DBOperationPid = spawn(fun() -> db_data_operation_process(DBPid) end),
							MysqlActivePid = spawn(fun() -> mysql_active_process(DBPid) end),
							HttpGpsPid = spawn(fun() -> http_gps_deamon(HttpGpsServer, uninit, 0, 0, 0, 0) end),
							%DBMaintainPid = spawn(fun() -> db_data_maintain_process(DBPid, DBOperationPid, Mode) end),
		                    ets:insert(msgservertable, {dbpid, DBPid}),
		                    ets:insert(msgservertable, {linkpid, LinkPid}),
		                    ets:insert(msgservertable, {dbtablepid, DBTablePid}),
		                    ets:insert(msgservertable, {ccpid, CCPid}),
		                    ets:insert(msgservertable, {vdrtablepid, VdrTablePid}),
		                    ets:insert(msgservertable, {drivertablepid, DriverTablePid}),
		                    ets:insert(msgservertable, {lastpostablepid, LastPosTablePid}),
							ets:insert(msgservertable, {dboperationpid, DBOperationPid}),
							ets:insert(msgservertable, {mysqlactivepid, MysqlActivePid}),
							ets:insert(msgservertable, {httpgpspid, HttpGpsPid}),
							%ets:insert(msgservertable, {dbmaintainpid, DBMaintainPid}),
		                    common:loginfo("DB client process PID is ~p", [DBPid]),
		                    common:loginfo("DB table deamon process PID is ~p", [DBTablePid]),
		                    common:loginfo("Code convertor process PID is ~p", [CCPid]),
		                    common:loginfo("VDR table processor process PID is ~p", [VdrTablePid]),
		                    common:loginfo("Driver table processor process PID is ~p", [DriverTablePid]),
		                    common:loginfo("Last pos table processor process PID is ~p", [LastPosTablePid]),
		                    common:loginfo("DB operation process PID is ~p", [DBOperationPid]),
							common:loginfo("Mysql active process PID is ~p", [MysqlActivePid]),
							common:loginfo("HTTP GPS process PID is ~p", [HttpGpsPid]),
		                    %common:loginfo("DB miantain process PID is ~p", [DBMaintainPid]),
		                    
							case HttpGpsState of
								1 ->
									HttpGpsPid ! init;
								_ ->
									ok
							end,
							
							common:loginfo("DB coding setting"),
				            DBPid ! {AppPid, conn, <<"set names 'utf8'">>},
				            receive
				                {AppPid, _} ->
									common:loginfo("DB coding setting returns"),
									case init_vdrdbtable(AppPid, DBPid) of
										{error, ErrorMsg} ->
											{error, ErrorMsg};
										ok ->
											case init_lastpostable(AppPid, DBPid) of
												{error, ErrorMsg} ->
													{error, ErrorMsg};
												ok ->
													case init_alarmtable(AppPid, DBPid) of
														{error, ErrorMsg1} ->
															{error, ErrorMsg1};
														ok ->
															case init_drivertable(AppPid, DBPid) of
																{error, ErrorMsg2} ->
																	{error, ErrorMsg2};
																ok ->
												                    CCPid ! {AppPid, create},
												                    receive
												                        created ->
												                            common:loginfo("Code convertor table is created"),
												                            {ok, AppPid}
												                        after ?TIMEOUT_CC_INIT_PROCESS ->
												                            {error, "ERROR : code convertor table is timeout"}
																	end
															end
													end
											end
									end
							after
								?DB_RESP_TIMEOUT ->
									{error, "ERROR : init db coding is timeout"}
							end
					end;
                {error, ErrMsg} ->
                    {error, ErrMsg}
            end;
        ignore ->
            common:logerror("Message server fails to start : ignore"),
            ignore;
        {error, Error} ->
            common:logerror("Message server fails to start : ~p", [Error]),
            {error, Error}
    end.

init_vdrdbtable(AppPid, DBPid) ->
	ets:delete_all_objects(vdrdbtable),
	common:loginfo("Init device/vehicle db table count."),
	DBPid ! {AppPid, conn, <<"select count(*) from device left join vehicle on vehicle.device_id = device.id">>},
	receive
		{AppPid, Count} ->
			RealCount = extract_vdrdbtable_count(Count),
			common:loginfo("Init device/vehicle db table count=~p", [RealCount]),
			init_vdrdbtable_once(AppPid, DBPid, 0, RealCount),
			common:loginfo("Init device/vehicle db table final count=~p", [ets:info(vdrdbtable,size)])
	after ?DB_RESP_TIMEOUT ->
		{error, "ERROR : init device/vehicle db table count is timeout"}
	end.

extract_vdrdbtable_count(Result) ->
	try
		%{data,{mysql_result,[{<<>>,<<"count(*)">>,21,'LONGLONG'}],[[24067]],0,0,[],0,[]}} = Result,
		common:loginfo("extract_vdrdbtable_count(Result) : ~p", [Result]),
		{_,{_,[{_,_,_,_}],[[Count]],_,_,_,_,_}} = Result,
		Count
	catch
		Ex:Msg ->
			common:logerror("Cannot extract device/vehicle db table count.\n(Exception)~p:(Message)~p~n", [Ex, Msg]),
			0
	end.	

init_vdrdbtable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
													   Count > 0,
													   is_integer(Index),
													   Index >= 0,
													   Index < Count,
													   Index + ?DB_HASH_UPDATE_ONCE_COUNT =< Count ->
	common:loginfo("Init device/vehicle db table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from device left join vehicle on vehicle.device_id = device.id order by reg_time desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Index + ?DB_HASH_UPDATE_ONCE_COUNT)])},
	receive
		{AppPid, Result} ->
			init_vdrdbtable_once(Result),
			init_vdrdbtable_once(AppPid, DBPid, Index+?DB_HASH_UPDATE_ONCE_COUNT, Count)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init device/vehicle db table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_vdrdbtable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
													   Count > 0,
													   is_integer(Index),
													   Index >= 0,
													   Index < Count,
													   Index+?DB_HASH_UPDATE_ONCE_COUNT > Count ->
	common:loginfo("Init device/vehicle db table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from device left join vehicle on vehicle.device_id = device.id order by reg_time desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Count-Index)])},
	receive
		{AppPid, Result} ->
			init_vdrdbtable_once(Result)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init device/vehicle db table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_vdrdbtable_once(_AppPid, _DBPid, _Count, _Index) ->
	ok.

init_vdrdbtable_once(Result) ->
	case vdr_handler:extract_db_resp(Result) of
		error ->
			common:logerror("Message server cannot init vdr db table");
		{ok, empty} ->
		    common:logerror("Message server init empty vdr db table");
		{ok, Records} ->
			try
				do_init_vdrdbtable_once(Records)
			catch
				_:Msg ->
					common:logerror("Message server fails to init vdr db table : ~p", [Msg])
			end
	end.

do_init_vdrdbtable_once(Result) when is_list(Result),
								length(Result) > 0 ->
	[H|T] = Result,
	{VDRID, VDRSerialNo, VDRAuthenCode, VehicleCode, VehicleID, DriverID} = vdr_handler:get_record_column_info(H),
	if
		VehicleCode =/= undefined andalso binary_part(VehicleCode, 0, 1) =/= <<"?">> ->
			VDRDBItem = #vdrdbitem{authencode=VDRAuthenCode, 
								   vdrid=VDRID, 
								   vdrserialno=VDRSerialNo,
								   vehiclecode=VehicleCode,
								   vehicleid=VehicleID,
								   driverid=DriverID},
			ets:insert(vdrdbtable, VDRDBItem),
			do_init_vdrdbtable_once(T);
		true ->
			common:logerror("Failt to insert Device/Vehicle : VDRAuthenCode ~p, VDRID ~p, VDRSerialNo ~p, VehicleCode ~p, VehicleID ~p, DriverID ~p",
							[VDRAuthenCode, VDRID, VDRSerialNo, VehicleCode, VehicleID, DriverID]),
			do_init_vdrdbtable_once(T)
	end;
do_init_vdrdbtable_once(_Result) ->
	ok.

init_drivertable(AppPid, DBPid) ->
	ets:delete_all_objects(drivertable),
	common:loginfo("Init driver table count."),
	DBPid ! {AppPid, conn, <<"select count(*) from driver">>},
	receive
		{AppPid, Count} ->
			RealCount = extract_drivertable_count(Count),
			common:loginfo("Init driver table count=~p", [RealCount]),
			init_drivertable_once(AppPid, DBPid, 0, RealCount),
			common:loginfo("Init driver table final count=~p", [ets:info(drivertable,size)])
	after ?DB_RESP_TIMEOUT ->
		{error, "ERROR : init driver table count is timeout"}
	end.

extract_drivertable_count(Result) ->
	try
		%{data,{mysql_result,[{<<>>,<<"count(*)">>,21,'LONGLONG'}],[[15018]],0,0,[],0,[]}} = Result,
		common:loginfo("extract_drivertable_count(Result) : ~p", [Result]),
		{_,{_,[{_,_,_,_}],[[Count]],_,_,_,_,_}} = Result,
		Count
	catch
		Ex:Msg ->
			common:logerror("Cannot extract driver table count.\n(Exception)~p:(Message)~p~n", [Ex, Msg]),
			0
	end.	

init_drivertable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
														Count > 0,
														is_integer(Index),
														Index >= 0,
														Index < Count,
														Index + ?DB_HASH_UPDATE_ONCE_COUNT =< Count ->
	common:loginfo("Init driver table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from driver order by id desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Index + ?DB_HASH_UPDATE_ONCE_COUNT)])},
	receive
		{AppPid, Result} ->
			init_drivertable_once(Result),
			init_drivertable_once(AppPid, DBPid, Index+?DB_HASH_UPDATE_ONCE_COUNT, Count)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init driver table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_drivertable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
														Count > 0,
														is_integer(Index),
														Index >= 0,
														Index < Count,
														Index+?DB_HASH_UPDATE_ONCE_COUNT > Count ->
	common:loginfo("Init driver table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from driver order by id desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Count-Index)])},
	receive
		{AppPid, Result} ->
			init_drivertable_once(Result)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init driver table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_drivertable_once(_AppPid, _DBPid, _Count, _Index) ->
	ok.

init_drivertable_once(DriverResult) ->
	case vdr_handler:extract_db_resp(DriverResult) of
		error ->
			common:logerror("Message server cannot init driver table");
		{ok, empty} ->
		    common:logerror("Message server init empty driver table");
		{ok, Records} ->
			try
				do_init_drivertable(Records)
			catch
				_:Msg ->
					common:logerror("Message server fails to init driver table : ~p", [Msg])
			end
	end.

do_init_drivertable(DriverResult) when is_list(DriverResult),
									   length(DriverResult) > 0 ->
	[H|T] = DriverResult,
	{<<"driver">>, <<"id">>, ID} = vdr_handler:get_record_field(<<"driver">>, H, <<"id">>),
	{<<"driver">>, <<"license_no">>, LicNo} = vdr_handler:get_record_field(<<"driver">>, H, <<"license_no">>),
	{<<"driver">>, <<"certificate_code">>, CertCode} = vdr_handler:get_record_field(<<"driver">>, H, <<"certificate_code">>),
	DriverItem = #driverinfo{driverid=ID, 
							 licno=LicNo, 
							 certcode=CertCode},
	%common:loginfo("Driver : ~p", [DriverItem]),
	ets:insert(drivertable, DriverItem),
	do_init_drivertable(T);
do_init_drivertable(_DriverResult) ->
	ok.

init_lastpostable(AppPid, DBPid) ->
	ets:delete_all_objects(lastpostable),
	common:loginfo("Init last pos table count."),
	DBPid ! {AppPid, conn, <<"select count(*) from vehicle_position_last">>},
	receive
		{AppPid, Count} ->
			RealCount = extract_lastpostable_count(Count),
			common:loginfo("Init last pos table count=~p", [RealCount]),
			init_lastpostable_once(AppPid, DBPid, 0, RealCount),
			common:loginfo("Init last pos table final count=~p", [ets:info(lastpostable,size)])
	after ?DB_RESP_TIMEOUT ->
		{error, "ERROR : init last pos table count is timeout"}
	end.

extract_lastpostable_count(Result) ->
	try
		%{data,{mysql_result,[{<<>>,<<"count(*)">>,21,'LONGLONG'}],[[15018]],0,0,[],0,[]}} = Result,
		common:loginfo("extract_lastpostable_count(Result) : ~p", [Result]),
		{_,{_,[{_,_,_,_}],[[Count]],_,_,_,_,_}} = Result,
		Count
	catch
		Ex:Msg ->
			common:logerror("Cannot extract last pos table count.\n(Exception)~p:(Message)~p~n", [Ex, Msg]),
			0
	end.	

init_lastpostable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
														Count > 0,
														is_integer(Index),
														Index >= 0,
														Index < Count,
														Index + ?DB_HASH_UPDATE_ONCE_COUNT =< Count ->
	common:loginfo("Init last pos table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from vehicle_position_last order by vehicle_id desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Index + ?DB_HASH_UPDATE_ONCE_COUNT)])},
	receive
		{AppPid, Result} ->
			init_lastpostable_once(Result),
			init_lastpostable_once(AppPid, DBPid, Index+?DB_HASH_UPDATE_ONCE_COUNT, Count)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init last pos table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_lastpostable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
														Count > 0,
														is_integer(Index),
														Index >= 0,
														Index < Count,
														Index+?DB_HASH_UPDATE_ONCE_COUNT > Count ->
	common:loginfo("Init driver table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from vehicle_position_last order by vehicle_id desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Count-Index)])},
	receive
		{AppPid, Result} ->
			init_lastpostable_once(Result)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init last pos table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_lastpostable_once(_AppPid, _DBPid, _Count, _Index) ->
	ok.

init_lastpostable_once(DriverResult) ->
	case vdr_handler:extract_db_resp(DriverResult) of
		error ->
			common:logerror("Message server cannot init last pos table");
		{ok, empty} ->
		    common:logerror("Message server init empty last pos table");
		{ok, Records} ->
			try
				do_init_lastpostable(Records)
			catch
				_:Msg ->
					common:logerror("Message server fails to init last pos table : ~p", [Msg])
			end
	end.

do_init_lastpostable(DriverResult) when is_list(DriverResult),
									   length(DriverResult) > 0 ->
	[H|T] = DriverResult,
	{<<"vehicle_position_last">>, <<"vehicle_id">>, ID} = vdr_handler:get_record_field(<<"vehicle_position_last">>, H, <<"vehicle_id">>),
	{<<"vehicle_position_last">>, <<"longitude">>, Lon} = vdr_handler:get_record_field(<<"vehicle_position_last">>, H, <<"longitude">>),
	{<<"vehicle_position_last">>, <<"latitude">>, Lat} = vdr_handler:get_record_field(<<"vehicle_position_last">>, H, <<"latitude">>),
	LastPosItem = #lastposinfo{vehicleid=ID, 
							 longitude=Lon*1000000.0, 
							 latitude=Lat*1000000.0},
	%common:loginfo("Driver : ~p", [DriverItem]),
	ets:insert(lastpostable, LastPosItem),
	do_init_lastpostable(T);
do_init_lastpostable(_DriverResult) ->
	ok.

init_alarmtable(AppPid, DBPid) ->
	ok.

init_alarmtable_dummy(AppPid, DBPid) ->
	ets:delete_all_objects(alarmtable),
	common:loginfo("Init alarm table count."),
	DBPid ! {AppPid, conn, <<"select count(*) from vehicle_alarm where isnull(clear_time)">>},
	receive
		{AppPid, Count} ->
			RealCount = extract_alarmtable_count(Count),
			common:loginfo("Init alarm table count=~p", [RealCount]),
			init_alarmtable_once(AppPid, DBPid, 0, RealCount),
			common:loginfo("Init alarm table final count=~p", [ets:info(alarmtable,size)])
	after ?DB_RESP_TIMEOUT ->
		{error, "ERROR : init alarm table count is timeout"}
	end.

extract_alarmtable_count(Result) ->
	try
		%{data,{mysql_result,[{<<>>,<<"count(*)">>,21,'LONGLONG'}],[[15018]],0,0,[],0,[]}} = Result,
		common:loginfo("extract_alarmtable_count(Result) : ~p", [Result]),
		{_,{_,[{_,_,_,_}],[[Count]],_,_,_,_,_}} = Result,
		Count
	catch
		Ex:Msg ->
			common:logerror("Cannot extract alarm table count.\n(Exception)~p:(Message)~p~n", [Ex, Msg]),
			0
	end.	

init_alarmtable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
													   Count > 0,
													   is_integer(Index),
													   Index >= 0,
													   Index < Count,
													   Index + ?DB_HASH_UPDATE_ONCE_COUNT =< Count ->
	common:loginfo("Init alarm table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from vehicle_alarm where isnull(clear_time) order by alarm_time desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Index + ?DB_HASH_UPDATE_ONCE_COUNT)])},
	receive
		{AppPid, Result} ->
			init_alarmtable_once(Result),
			init_alarmtable_once(AppPid, DBPid, Index+?DB_HASH_UPDATE_ONCE_COUNT, Count)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init alarm table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_alarmtable_once(AppPid, DBPid, Index, Count) when is_integer(Count),
													   Count > 0,
													   is_integer(Index),
													   Index >= 0,
													   Index < Count,
													   Index+?DB_HASH_UPDATE_ONCE_COUNT > Count ->
	common:loginfo("Init alarm table index=~p", [Index]),
	DBPid ! {AppPid, conn, binary:list_to_bin([<<"select * from vehicle_alarm where isnull(clear_time) order by alarm_time desc limit ">>, 
											   integer_to_binary(Index), <<", ">>, integer_to_binary(Count-Index)])},
	receive
		{AppPid, Result} ->
			init_alarmtable_once(Result)
	after ?DB_RESP_TIMEOUT ->
		{error, lists:append(["ERROR : init alarm table is timeout when index=", integer_to_list(Index), " and count=", integer_to_list(Count), "."])}
	end;
init_alarmtable_once(_AppPid, _DBPid, _Count, _Index) ->
	ok.

init_alarmtable_once(AlarmResult) ->
	case vdr_handler:extract_db_resp(AlarmResult) of
		error ->
			common:logerror("Message server cannot init alarm table");
		{ok, empty} ->
		    common:logerror("Message server init empty alarm table");
		{ok, Records} ->
			try
				do_init_alarmtable(Records)
			catch
				_:Msg ->
					common:logerror("Message server fails to init alarm table : ~p", [Msg])
			end
	end.

do_init_alarmtable(AlarmResult) when is_list(AlarmResult),
									 length(AlarmResult) > 0 ->
	[H|T] = AlarmResult,
	{<<"vehicle_alarm">>, <<"vehicle_id">>, VehicleID} = vdr_handler:get_record_field(<<"vehicle_alarm">>, H, <<"vehicle_id">>),
	{<<"vehicle_alarm">>, <<"type_id">>, TypeID} = vdr_handler:get_record_field(<<"vehicle_alarm">>, H, <<"type_id">>),
	{<<"vehicle_alarm">>, <<"alarm_time">>, {datetime, AlarmTime}} = vdr_handler:get_record_field(<<"vehicle_alarm">>, H, <<"alarm_time">>),
	%{<<"vehicle_alarm">>, <<"sn">>, SN} = vdr_handler:get_record_field(<<"vehicle_alarm">>, H, <<"sn">>),
	%  AlarmTime is {{YY,MM,DD},{Hh,Mm,Ss}}
	if
		VehicleID =/= undefined andalso TypeID =/= undefined andalso AlarmTime =/= undefined ->
			AlarmItem = #alarmitem{vehicleid=VehicleID, 
								   type=TypeID, 
								   time=AlarmTime}, 
								   %sn=SN},
			ets:insert(alarmtable, AlarmItem),
			do_init_alarmtable(T);
		true ->
			common:logerror("Failt to insert alarm : VehicleID ~p, TypeID ~p, ClearTime ~p",
							[VehicleID, TypeID, AlarmTime]),
			do_init_alarmtable(T)
	end;
do_init_alarmtable(_AlarmResult) ->
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% This process will update device\vehicle table and alarm table every half an hour
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%db_data_maintain_process(DBPid, DBOperationPid, Mode) ->
%	ok.
%
%db_data_maintain_process_dummy(DBPid, DBOperationPid, Mode) ->
%	receive
%		stop ->
%			common:logerror("DB maintain process receive unknown msg.");
%		_ ->
%			db_data_maintain_process(DBPid, DBOperationPid, Mode)
%	after ?DB_HASH_UPDATE_INTERVAL ->
%			if
%				Mode == 2 orelse Mode == 1 ->
%					common:loginfo("DB maintain process is active."),
%					Pid = self(),
%					DBPid ! {Pid, conn, <<"set names 'utf8'">>},
%					receive
%						{Pid, _} ->
%							ok
%					end,
%					DBOperationPid ! {Pid, update, devicevehicle},
%					receive
%						{Pid, updateok} ->
%							ok
%					end,
%					DBOperationPid ! {Pid, update, alarm},
%					receive
%						{Pid, updateok} ->
%							ok
%					end,
%					db_data_maintain_process(DBPid, DBOperationPid, Mode);
%				true ->
%					common:loginfo("DB maintain process is active without DB operation."),
%					db_data_maintain_process(DBPid, DBOperationPid, Mode)
%			end
%	end.			

mysql_active_process(DBPid) ->
	receive
		stop ->
			common:logerror("Mysql active process stops.");
		_ ->
			mysql_active_process(DBPid)
	after ?MAX_DB_PROC_WAIT_INTERVAL ->
			DBPid ! {self(), active},
			mysql_active_process(DBPid)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% This process will operate device\vehicle table and alarm table
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
db_data_operation_process(DBPid) ->
	receive
		stop ->
			common:logerror("DB operation process stops.");
		%{Pid, update, devicevehicle} ->
		%	common:loginfo("DB operation process update device/vehicle."),
		%	ProcPid = self(),
		%	init_vdrdbtable(ProcPid, DBPid),
		%	Pid ! {Pid, updateok},
		%	db_data_operation_process(DBPid);
		%{Pid, update, alarm} ->
		%	common:loginfo("DB operation process update alarm."),
		%	ProcPid = self(),
		%	init_alarmtable(ProcPid, DBPid),
		%	Pid ! {Pid, updateok},
		%	db_data_operation_process(DBPid);
		{_Pid, replace, alarm, VehicleID, AlarmList} ->
			ets:delete(alarmtable, VehicleID),
			ets:insert(alarmtable, AlarmList),
			%Pid ! {Pid, relpaceok},
			db_data_operation_process(DBPid);
		{Pid, lookup, Table, Key} ->
			Res = ets:lookup(Table, Key),
			Pid ! {Pid, Res},
			db_data_operation_process(DBPid);
		{Pid, insert, Table, Object} ->
			ets:insert(Table, Object),
			Pid ! {Pid, insertok},
			db_data_operation_process(DBPid);
		{_Pid, insert, Table, Object, noresp} ->
			ets:insert(Table, Object),
			db_data_operation_process(DBPid);
		{Pid, delete, Table, Key} ->
			ets:delete(Table, Key),
			Pid ! {Pid, deleteok},
			db_data_operation_process(DBPid);
		{_Pid, delete, Table, Key, noresp} ->
			ets:delete(Table, Key),
			db_data_operation_process(DBPid);
		{Pid, clear, Table} ->
			ets:delete_all_objects(Table),
			Pid ! {Pid, clearok},
			db_data_operation_process(DBPid);
		{_Pid, clear, Table, noresp} ->
			ets:delete_all_objects(Table),
			db_data_operation_process(DBPid);
		Msg ->
			common:logerror("DB operation process receive unknown msg : ~p", [Msg]),
			db_data_operation_process(DBPid)
	end.

vdrtable_insert_delete_process() ->
	receive
		stop ->
			common:loginfo("VDR table insert/delete process stops.");
		{Pid, insert, Object} ->
			ets:insert(vdrtable, Object),
			Pid ! {Pid, ok},
			vdrtable_insert_delete_process();
		{_Pid, insert, Object, noresp} ->
			ets:insert(vdrtable, Object),
			vdrtable_insert_delete_process();
		{Pid, delete, Key} ->
			ets:delete(vdrtable, Key),
			Pid ! {Pid, ok},
			vdrtable_insert_delete_process();
		{_Pid, delete, Key, noresp} ->
			ets:delete(vdrtable, Key),
			vdrtable_insert_delete_process();
		{Pid, count} ->
			Count = ets:info(vdrtable, size),
			Pid ! {Pid, Count},
			vdrtable_insert_delete_process();
		{Pid, lookup, Key} ->
			Res = ets:lookup(vdrtable, Key),
			Pid ! {Pid, Res},
			vdrtable_insert_delete_process();
		_ ->
			common:logerror("VDR table insert/delete process receive unknown msg."),
			vdrtable_insert_delete_process()
	end.

drivertable_insert_delete_process() ->
	receive
		stop ->
			common:loginfo("Driver table insert/delete process stops.");
		{Pid, checkdid, DriverID} ->
			IsInt = is_integer(DriverID),
			if
				IsInt == true ->
				    DriverInfos = ets:match(drivertable, {'$1',
														  DriverID, '_', '_'}),
		    		DriverInfosCount = length(DriverInfos),
					if
						DriverInfosCount > 0 ->
							Pid ! {Pid, 1};
						true ->
							Pid ! {Pid, 0}
					end;
				true ->
					Pid ! {Pid, 0}
			end,					
			drivertable_insert_delete_process();
		{Pid, checkcc, CertCode} ->
			IsList = is_list(CertCode),
			if
				IsList == true ->
					try
						CertCodeBin = erlang:list_to_binary(CertCode),
					    DriverInfos = ets:match(drivertable, {'$1',
															  '_', '_', CertCodeBin}),
			    		DriverInfosCount = length(DriverInfos),
						if
							DriverInfosCount > 0 ->
								Pid ! {Pid, 1};
							true ->
								Pid ! {Pid, 0}
						end
					catch
						_:_ ->
							Pid ! {Pid, 0}
					end;
				true ->
					IsBin = is_binary(CertCode),
					if
						IsBin == true ->
					    DriverInfos = ets:match(drivertable, {'$1',
															  '_', '_', CertCode}),
			    		DriverInfosCount = length(DriverInfos),
						if
							DriverInfosCount > 0 ->
								Pid ! {Pid, 1};
							true ->
								Pid ! {Pid, 0}
						end
					end
			end,					
			drivertable_insert_delete_process();
		{Pid, insert, DriverInfo} ->
			common:loginfo("Insert driver info : ~p", [DriverInfo]),
			[DriverID, LicNo, CertCode] = DriverInfo,
			DriverInfoItem = #driverinfo{driverid=DriverID, licno=LicNo, certcode=CertCode},
			ets:insert(drivertable, DriverInfoItem),
			drivertable_insert_delete_process();
		{Pid, get, CertCode} ->
			IsList = is_list(CertCode),
			if
				IsList == true ->
					try
						CertCodeBin = erlang:list_to_binary(CertCode),
					    DriverInfos = ets:match(drivertable, {'_',
															  '$1', '_', CertCodeBin}),
			    		DriverInfosCount = length(DriverInfos),
						if
							DriverInfosCount == 1 ->
								[[DriverID]] = DriverInfos,
								common:loginfo("Get driver id ~p by certificate_code ~p", [DriverID, CertCode]),
								Pid ! {Pid, DriverID};
							true ->
								Pid ! {Pid, 0}
						end
					catch
						_:_ ->
							Pid ! {Pid, 0}
					end;
				true ->
					IsBin = is_binary(CertCode),
					if
						IsBin == true ->
					    DriverInfos = ets:match(drivertable, {'_',
															  '$1', '_', CertCode}),
			    		DriverInfosCount = length(DriverInfos),
						if
							DriverInfosCount > 0 ->
								[[DriverID]] = DriverInfos,
								common:loginfo("Get driver id ~p by certificate_code ~p", [DriverID, CertCode]),
								Pid ! {Pid, DriverID};
							true ->
								Pid ! {Pid, 0}
						end
					end
			end,					
			drivertable_insert_delete_process();
		{Pid, count} ->
			Count = ets:info(drivertable,size),
			Pid ! {Pid, Count},
			drivertable_insert_delete_process();
		_ ->
			common:logerror("Driver table insert/delete process receive unknown msg."),
			drivertable_insert_delete_process()
	end.

lastpostable_insert_delete_process() ->
	receive
		stop ->
			common:loginfo("Last pos table insert/delete process stops.");
		{Pid, get, VID} ->
		    Infos = ets:match(lastpostable, {'_', 
											VID, '$1', '$2'}),
			InfoCount = length(Infos),
			if
				InfoCount == 1 ->	
					[[Lon, Lat]] = Infos,
					Pid ! {Pid, [Lon, Lat]};
				true ->
					Pid ! {Pid, [0.0, 0.0]}
			end,
			lastpostable_insert_delete_process();
		{Pid, set, Info} ->
			[VID, Lon, Lat] = Info,
		    Infos = ets:match(lastpostable, {'$1', 
											VID, '_', '_'}),
			InfoCount = length(Infos),
			if
				InfoCount == 0 ->	
					LastPosItem = #lastposinfo{vehicleid=VID,longitude=Lon,latitude=Lat},
					ets:insert(lastpostable, LastPosItem);
				true ->
					ok
			end,
			lastpostable_insert_delete_process();
		{Pid, count} ->
			Count = ets:info(lastpostable,size),
			Pid ! {Pid, Count},
			lastpostable_insert_delete_process();
		_ ->
			common:logerror("Last pos table insert/delete process receive unknown msg."),
			lastpostable_insert_delete_process()
	end.

%vdr_resp_process() ->
%	receive
%		stop ->
%			common:loginfo("VDR response process stops.");
%		{Pid, Socket, Msg} ->
%			vdr_resp_process(),
%			%common:loginfo("Msg from VDR ~p to VDRPid ~p : ~p", [Pid, self(), Msg]),
%			try gen_tcp:send(Socket, Msg)
%		    catch
%		        _:Ex ->
%		            common:logerror("Exception when gen_tcps:send ~p : ~p", [Msg, Ex])
%		    end,
%			Pid ! {Pid, ok};
%		{_Pid, Socket, Msg, noresp} ->
%			vdr_resp_process(),
%			%common:loginfo("Msg from VDR ~p to VDRPid ~p : ~p", [Pid, self(), Msg]),
%			try gen_tcp:send(Socket, Msg)
%		    catch
%		        _:Ex ->
%		            common:logerror("Exception when gen_tcps:send ~p : ~p", [Msg, Ex])
%		    end;
%		Unknown ->
%			common:loginfo("Msg from VDR to VDRPid unknwon : ~p", [Unknown]),
%			vdr_resp_process()
%	end.

%%%
%%%
%%%
stop(_State) ->
    [{dbpid, DBPid}] = ets:lookup(msgservertable, dbpid),
    case DBPid of
        undefined ->
            ok;
        _ ->
            DBPid ! stop
    end,
    [{vdrtablepid, VdrTablePid}] = ets:lookup(msgservertable, vdrtablepid),
    case VdrTablePid of
        undefined ->
            ok;
        _ ->
            VdrTablePid ! stop
    end,
    [{dbmaintainpid, DBMaintainPid}] = ets:lookup(msgservertable, dbmaintainpid),
    case DBMaintainPid of
        undefined ->
            ok;
        _ ->
            DBMaintainPid ! stop
    end,
    [{dboperationpid, DBOperationPid}] = ets:lookup(msgservertable, dboperationpid),
    case DBOperationPid of
        undefined ->
            ok;
        _ ->
            DBOperationPid ! stop
    end,
    [{mysqlactivepid, MysqlActivePid}] = ets:lookup(msgservertable, mysqlactivepid),
    case MysqlActivePid of
        undefined ->
            ok;
        _ ->
            MysqlActivePid ! stop
    end,
    [{vdrresppid, VdrRespPid}] = ets:lookup(msgservertable, vdrresppid),
    case VdrRespPid of
        undefined ->
            ok;
        _ ->
            VdrRespPid ! stop
    end,
    [{wspid, WSPid}] = ets:lookup(msgservertable, wspid),
    case WSPid of
        undefined ->
            ok;
        _ ->
            WSPid ! stop
    end,
    [{linkpid, LinkPid}] = ets:lookup(msgservertable, linkpid),
    case LinkPid of
        undefined ->
            ok;
        _ ->
            LinkPid ! stop
    end,
    [{dbtablepid, DBTablePid}] = ets:lookup(msgservertable, dbtablepid),
    case DBTablePid of
        undefined ->
            ok;
        _ ->
            DBTablePid ! stop
    end,
    [{ccpid, CCPid}] = ets:lookup(msgservertable, ccpid),
    case CCPid of
        undefined ->
            ok;
        _ ->
            CCPid ! stop
    end,
    [{drivertablepid, DriverTablePid}] = ets:lookup(msgservertable, drivertablepid),
    case DriverTablePid of
        undefined ->
            ok;
        _ ->
            DriverTablePid ! stop
    end,
    [{lastpostablepid, LastPosTablePid}] = ets:lookup(msgservertable, lastpostablepid),
    case LastPosTablePid of
        undefined ->
            ok;
        _ ->
            DriverTablePid ! stop
    end,
    [{httpgpspid, HttpGpsPid}] = ets:lookup(msgservertable, httpgpspid),
    case HttpGpsPid of
        undefined ->
            ok;
        _ ->
            HttpGpsPid ! stop
    end,
    error_logger:info_msg("Message server stops.").

code_convertor_process() ->
    receive
        {Pid, create} ->
            code_convertor:init_code_table(),
            %common:loginfo("CC process ~p : code table is initialized", [self()]),
            Pid ! created,
            code_convertor_process();
        {Pid, gbktoutf8, Src} ->
            try
                %common:loginfo("CC process ~p : source GBK from ~p : ~p", [self(), Pid, Src]),
                Value = code_convertor:to_utf8(Src),
                %common:loginfo("CC process ~p : dest UTF8 : ~p", [self(), Value]),
                Pid ! code_convertor:to_utf8(Src)
            catch
                _:_ ->
                    common:logerror("CC process ~p : EXCEPTION when converting GBK to UTF8 : ~p", [self(), Src]),
                    Pid ! Src
            end,
            code_convertor_process();
        {Pid, gbk2utf8, Src} ->
            try
                %common:loginfo("CC process ~p : source GBK from ~p : ~p", [self(), Pid, Src]),
                Value = code_convertor:to_utf8(Src),
                %common:loginfo("CC process ~p : dest UTF8 : ~p", [self(), Value]),
                Pid ! code_convertor:to_utf8(Src)
            catch
                _:_ ->
                    common:logerror("CC process ~p : EXCEPTION when converting GBK to UTF8 : ~p", [self(), Src]),
                    Pid ! Src
            end,
            code_convertor_process();
        {Pid, utf82gbk, Src} ->
            try
                %common:loginfo("CC process ~p : source UTF8 from ~p : ~p", [self(), Pid, Src]),
                Value = code_convertor:to_gbk(Src),
                %common:loginfo("CC process ~p : dest GBK : ~p", [self(), Value]),
                Pid ! Value
            catch
                _:_ ->
                    common:logerror("CC process ~p : EXCEPTION when converting UTF8 to GBK : ~p", [self(), Src]),
                    Pid ! Src
            end,
            code_convertor_process();
        {Pid, utf8togbk, Src} ->
            try
                %common:loginfo("CC process ~p : source UTF8 from ~p : ~p", [self(), Pid, Src]),
                Value = code_convertor:to_gbk(Src),
                %common:loginfo("CC process ~p : dest GBK : ~p", [self(), Value]),
                Pid ! Value
            catch
                _:_ ->
                    common:logerror("CC process ~p : EXCEPTION when converting UTF8 to GBK : ~p", [self(), Src]),
                    Pid ! Src
            end,
            code_convertor_process();
        stop ->
            ok;
		{Pid, Msg} ->
			%common:loginfo("CC process ~p : unknown message from ~p : ~p", [self(), Pid, Msg]),
			Pid ! msg,
			code_convertor_process();
		UnknownMsg ->
			%common:loginfo("CC process ~p : unknown message : ~p", [self(), UnknownMsg]),
			code_convertor_process()
	%after ?CC_PID_TIMEOUT ->
	%		common:loginfo("CC process ~p : current waiting timeout and start another waiting", [self()]),
	%		code_convertor_process()
    end.
            
connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
						LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
						UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
						ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
						VDRMsgGot, VDRMsgSent) ->
	receive
		stop ->
			ok;
		{_Pid, test} ->
			connection_info_process(Conn+1, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, conn} ->
			connection_info_process(Conn+1, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, chardisc} ->
			connection_info_process(Conn, CharDisc+1, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, regdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc+1, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, authdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc+1, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, errdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc+1, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, clientdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc+1, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, lenerr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr+1, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, parerr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr+1, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, spliterr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr+1, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, resterr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr+1, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, packerr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr+1, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, vdrtimeout} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr+1,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, unauthdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc+1, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, exitdisc} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc+1, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, vdrerr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr+1, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, unvdrerr} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr+1, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, msgex} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx+1, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, gwstop} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop+1,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, servermsg} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg+1, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, invalidmsgerror} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg+1, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, dbmsgstored, N} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored+N, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, dbmsgsent, N} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent+N, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, dbmsgunknown} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown+1, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, dbmsgerror} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError+1, 
									VDRMsgGot, VDRMsgSent);
		{_Pid, vdrmsggot} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot+1, VDRMsgSent);
		{_Pid, vdrmsgsent} ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent+1);
		{_Pid, clear} ->
			connection_info_process(0, 0, 0, 0, 0, 
									0, 0, 0, 0, 0, 
									0, 0, 0, 0, 0, 
									0, 0, 0, 0, 0, 
									0, 0, 0, 0, 0,
									0);
		{Pid, count} ->
			Pid ! {Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
				   LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
				   UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
				   ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
				   VDRMsgGot, VDRMsgSent},
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent);
		_ ->
			connection_info_process(Conn, CharDisc, RegDisc, AuthDisc, ErrDisc, ClientDisc, 
									LenErr, ParErr, SplitErr, RestErr, PackErr, TimeoutErr,
									UnauthDisc, ExitDisc, VdrErr, UnvdrErr, MsgEx, GWStop,
									ServerMsg, InvalidMsg, DBMsgStored, DBMsgSent, DBMsgUnknown, DBMsgError, 
									VDRMsgGot, VDRMsgSent)
	end.

%%%
%%% Will wait 20s
%%%
receive_db_ws_init_msg(WSOK, DBOK, Count, Mode) ->
    if
        Count >= 20 ->
			if
				Mode == 2 ->
		            if
		                WSOK == false andalso DBOK == false ->
		                    {error, "DB and WS both are not ready"};
		                WSOK == true andalso DBOK == false ->
		                    {error, "DB is not ready"};
		                WSOK == false andalso DBOK == true ->
		                    {error, "WS is not ready"};
		                WSOK == true andalso DBOK == true ->
							common:loginfo("DB is ok and WS is ok."),
		                    ok;
		                true ->
		                    {error, "Unknown DB and WS states"}
		            end;
				Mode == 1 ->
		            if
		                DBOK == true ->
							common:loginfo("DB is ok."),
		                    ok;
		                DBOK == false ->
		                    {error, "DB is not ready"};
		                true ->
		                    {error, "Unknown DB and WS states"}
		            end;
				true ->
                    ok
			end;
        true ->
			if
				Mode == 2 ->
					if
		                WSOK == true andalso DBOK == true ->
		                    ok;
						true ->
				            receive
				                {_DBPid, dbok} ->
				                    if
				                        WSOK == true ->
											common:loginfo("DB is ok after WS is ok."),
				                            ok;
				                        true ->
				                            receive_db_ws_init_msg(WSOK, true, Count+1, Mode)
				                    end;
				                {_WSPid, wsok} ->
				                    if
				                        DBOK == true ->
											common:loginfo("WS is ok after DB is ok."),
				                            ok;
				                        true ->
				                            receive_db_ws_init_msg(true, DBOK, Count+1, Mode)
				                    end;
				                _ ->
				                    receive_db_ws_init_msg(WSOK, DBOK, Count+1, Mode)
				            after ?WAIT_LOOP_INTERVAL ->
				                    receive_db_ws_init_msg(WSOK, DBOK, Count+1, Mode)
				            end
					end;
				Mode == 1 ->
					if
		                DBOK == true ->
		                    ok;
						true ->
				            receive
				                {_DBPid, dbok} ->
									common:loginfo("DB is ok."),
									ok;
				                _ ->
				                    receive_db_ws_init_msg(WSOK, DBOK, Count+1, Mode)
				            after ?WAIT_LOOP_INTERVAL ->
				                    receive_db_ws_init_msg(WSOK, DBOK, Count+1, Mode)
				            end
					end;
				true ->
                    ok
			end
    end.                

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
db_table_deamon() ->
    Today = erlang:localtime(),%today(),
    Tomorrow = add(Today, 1),
    {{Year, Month, Day}, _} = Today,
    {{Year1, Month1, Day1}, _} = Tomorrow,
    YearS = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Year)),
    MonthS = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Month)),
    DayS = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Day)),
    Year1S = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Year1)),
    Month1S = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Month1)),
    Day1S = vdr_data_processor:get_2_number_integer_from_oct_string(integer_to_list(Day1)),
    Bin = list_to_binary([common:integer_to_2byte_binary(YearS),
              common:integer_to_2byte_binary(MonthS),
              common:integer_to_2byte_binary(DayS)]),
    Bin1 = list_to_binary([common:integer_to_2byte_binary(Year1S),
               common:integer_to_2byte_binary(Month1S),
               common:integer_to_2byte_binary(Day1S)]),
    [{dbpid, DBPid}] = ets:lookup(msgservertable, dbpid),
    [{dbname, DBName}] = ets:lookup(msgservertable, dbname),
	DBNameBin = list_to_binary(DBName),
    case DBPid of
        undefined ->
            ok;
        _ ->
            Pid = self(),
            error_logger:info_msg("Check table ~p.vehicle_position_~p", [DBName, binary_to_list(Bin)]),
            DBPid ! {Pid, conn, list_to_binary([<<"CREATE TABLE IF NOT EXISTS ">>,
												DBNameBin,
												<<".vehicle_position_">>,
												Bin,
												<<" LIKE vehicle_position">>])},
            receive
                {Pid, Result1} ->
                    Result1
            end,
            error_logger:info_msg("Check table ~p.vehicle_position_~p", [DBName, binary_to_list(Bin1)]),
            DBPid ! {Pid, conn, list_to_binary([<<"CREATE TABLE IF NOT EXISTS ">>,
												DBNameBin,
												<<".vehicle_position_">>,
												Bin1,
												<<" LIKE vehicle_position">>])},
            receive
                {Pid, Result2} ->
                    Result2
            end
    end,
	receive
		stop ->
			ok;
		_ ->
			db_table_deamon()
	after 23*60*60*1000 ->
			db_table_deamon()
	end.			

%today() -> erlang:localtime().
%tomorrow() -> add(today(), 1).

add(Date, second) ->
    add(Date, 1, seconds);
add(Date, minute) ->
    add(Date, 1, minutes);
add(Date, hour) ->
    add(Date, 1, hours);
add(Date, day) ->
    add(Date, 1);
add(Date, week) ->
    add(Date, 1, weeks);
add(Date, month) ->
    add(Date, 1, months);
add(Date, year) ->
    add(Date, 1, years);
add(Date, N)  ->
    add(Date, N, days).

add(DateTime, N, seconds) ->
    T1 = calendar:datetime_to_gregorian_seconds(DateTime),
    T2 = T1 + N,
    calendar:gregorian_seconds_to_datetime(T2);
add(DateTime, N, minutes) ->
    add(DateTime, 60*N, seconds);
add(DateTime, N, hours) ->
    add(DateTime, 60*N, minutes);
add(DateTime, N, days) ->
    add(DateTime, 24*N, hours);
add(DateTime, N, weeks) ->
    add(DateTime, 7*N, days);
% Adding months is a bit tricky.
add({{YYYY, MM, DD}=Date, Time}, 0, months) ->
    case calendar:valid_date(Date) of
	true  -> {Date, Time};
	false -> add({{YYYY, MM, DD-1}, Time}, 0, months) % Oops, too many days in this month,
                                                          % Remove a day and try again.
    end;
add({{YYYY, MM, DD}, Time}, N, months) when N > 0 andalso MM < 12 ->
    add({{YYYY, MM+1, DD}, Time}, N-1, months);
add({{YYYY, MM, DD}, Time}, N, months) when N > 0 andalso MM =:= 12 ->
    add({{YYYY+1, 1, DD}, Time}, N-1, months); 
add({{YYYY, MM, DD}, Time}, N, months) when N < 0 andalso MM > 1 ->
    add({{YYYY, MM-1, DD}, Time}, N+1, months);
add({{YYYY, MM, DD}, Time}, N, months) when N < 0 andalso MM =:= 1 ->
    add({{YYYY-1, 12, DD}, Time}, N+1, months);
add(Date, N, years) ->
    add(Date, 12*N, months).
     

http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount) ->
	receive
		{Pid, normal, Request} ->
			[LonReq, LatReq] = Request,
			case convertrequest(Request) of
				{ok, SRequest} ->
					FullRequest = lists:append(["http://", 
											   InitialIPPort, 
											   "/coordinate/simple?sid=15001&xys=", 
											   SRequest, 
											   "&resType=xml&rid=123&key=1831beb01605f760589221fdd6f2cdfb7412a767dbc0f004854457f59fb16ab863a3a1722cef553f"]),
					%common:loginfo("Position : ", [FullRequest]),
					case State of
						inited ->
							try
								case httpc:request(FullRequest) of
									{ok, {{_Version, 200, _ReasonPhrase}, _Headers, Body}} ->
										BodyB = list_to_binary(Body),
										BinParts = binary:split(BodyB, [<<"<xys>">>, <<"</xys>">>], [global]),
										case length(BinParts) of
											3 ->
												[_, LonLatBinS, _] = BinParts,
												LonLatBinL = binary:split(LonLatBinS, [<<",">>], [global]),
												case length(LonLatBinL) of
													2 ->
														[LonBin, LatBin] = LonLatBinL,
														try
															Lon = erlang:binary_to_float(LonBin),
															Lat = erlang:binary_to_float(LatBin),
															Request2 = [Lon, Lat],
															case convertrequest(Request2) of
																{ok, SRequest2} ->
																	FullRequest2 = lists:append(["http://",
																							    InitialIPPort, 
																							    "/rgeocode/simple?sid=7001&region=", 
																							    SRequest2, 
																							    "&poinum=1&range=3000&encode=UTF-8&resType=json&rid=$rid&roadnum=1&crossnum=0&show_near_districts=true&key=1831beb01605f760589221fdd6f2cdfb7412a767dbc0f004854457f59fb16ab863a3a1722cef553f"]),
																	%common:loginfo("Address : ", [FullRequest2]),
																	try
																		case httpc:request(FullRequest2) of
																			{ok, {{_Version2, 200, _ReasonPhrase2}, _Headers2, Body2}} ->
																				BodyB2 = list_to_binary(Body2),
																				FullAddrBin2 = get_full_address(BodyB2),
																				case FullAddrBin2 of
																					<<>> ->
																						Pid ! [Lon, Lat, []];
																					_ ->
																						FullAddr = binary_to_list(FullAddrBin2),
																						Pid ! [Lon, Lat, FullAddr]
																				end,
																				http_gps_deamon(InitialIPPort, State, Count+1, ACount, FCount, FACount);
																			{error, Reason2} ->
																				common:logerror("HTTP GPS address request fails : ~p", [Reason2]),
																				Pid ! [Lon, Lat, []],
																				http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
																		end
																	catch
																		Oper2:ExReason2 ->
																			common:logerror("HTTP GPS address request exception : (~p) ~p", [Oper2, ExReason2]),
																			Pid ! [Lon, Lat, []],
																			http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
																	end;
																error ->
																	common:logerror("HTTP GPS address request fails because of conversion error"),
																	Pid ! [Lon, Lat, []],
																	http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
															end
														catch
															_:_ ->
																common:logerror("HTTP GPS request fails : cannot convert longitude and latitude ~p", [Body]),
																Pid ! [LonReq, LatReq, []],
																http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
														end;
													_ ->
														common:logerror("HTTP GPS request fails : cannot convert longitude/latitude ~p", [Body]),
														Pid ! [LonReq, LatReq, []],
														http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
												end;
											_ ->
												common:logerror("HTTP GPS request fails : response error ~p", [Body]),
												Pid ! [LonReq, LatReq, []],
												http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
										end;
									{error, Reason} ->
										common:logerror("HTTP GPS request fails : ~p", [Reason]),
										Pid ! [LonReq, LatReq, []],
										http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
								end
							catch
								Oper:ExReason ->
									common:logerror("HTTP GPS request exception : (~p) ~p", [Oper, ExReason]),
									Pid ! [LonReq, LatReq, []],
									http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
							end;
						uninit ->
							%common:logerror("HTTP GPS request fails because of uninit state"),
							Pid ! [LonReq, LatReq, []],
							http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount);
						_ ->
							common:logerror("HTTP GPS request fails because of unknown state"),
							Pid ! [LonReq, LatReq, []],
							http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
					end;
				error ->
					common:logerror("HTTP GPS request fails because of unknown state"),
					Pid ! [LonReq, LatReq, []],
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount+1, FACount)
			end;
		{Pid, abnormal, Request} ->
			[LonReq, LatReq] = Request,
			case convertrequest(Request) of
				{ok, SRequest} ->
					FullRequest = lists:append(["http://", 
											   InitialIPPort, 
											   "/rgeocode/simple?sid=7001&region=", 
											   SRequest, 
											   "&poinum=1&range=3000&encode=UTF-8&resType=json&rid=$rid&roadnum=1&crossnum=0&show_near_districts=true&key=1831beb01605f760589221fdd6f2cdfb7412a767dbc0f004854457f59fb16ab863a3a1722cef553f"]),
					case State of
						inited ->
							try
								case httpc:request(FullRequest) of
									{ok, {{_Version, 200, _ReasonPhrase}, _Headers, Body}} ->
										BodyB = list_to_binary(Body),
										FullAddrBin = get_full_address(BodyB),
										case FullAddrBin of
											<<>> ->
												Pid ! [LonReq, LatReq, []];
											_ ->
												FullAddr = binary_to_list(FullAddrBin),
												Pid ! [LonReq, LatReq, FullAddr]
										end,
										http_gps_deamon(InitialIPPort, State, Count, ACount+1, FCount, FACount);
									{error, Reason} ->
										common:logerror("HTTP GPS address request fails : ~p", [Reason]),
										Pid ! [LonReq, LatReq, []],
										http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount+1)
								end
							catch
								Oper:ExReason ->
									common:logerror("HTTP GPS address request exception : (~p) ~p", [Oper, ExReason]),
									Pid ! [LonReq, LatReq, []],
									http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount+1)
							end;
						uninit ->
							%common:logerror("HTTP GPS address request fails because of uninit state"),
							Pid ! [LonReq, LatReq, []],
							http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount+1);
						_ ->
							common:logerror("HTTP GPS request fails because of unknown state"),
							Pid ! [LonReq, LatReq, []],
							http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount+1)
					end;
				error ->
					common:logerror("HTTP GPS address request fails because of conversion error"),
					Pid ! [LonReq, LatReq, []],
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount+1)
			end;
		{server, IPPort} ->
			http_gps_deamon(IPPort, State, Count, ACount, FCount, FACount);
		init ->
			case State of
				uninit ->
					case inets:start() of
						ok ->
							http_gps_deamon(InitialIPPort, inited, 0, 0, 0, 0);
						{error, Reason} ->
							common:logerror("Cannot start HTTP GPS inets : ~p", [Reason]),
							http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount)
					end;
				inited ->
					common:logerror("HTTP GPS inets already inited for init command"),
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount);
				_ ->
					common:logerror("HTTP GPS inets unknown state for init command"),
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount)
			end;
		release ->
			case State of
				uninit ->
					common:logerror("HTTP GPS inets already uninit for release command"),
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount);
				inited ->
					inets:stop(),
					http_gps_deamon(InitialIPPort, uninit, Count, ACount, FCount, FACount);
				_ ->
					common:logerror("HTTP GPS inets unknwon state for release command"),
					http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount)
			end;
		stop ->
			case State of
				uninit ->
					common:logerror("HTTP GPS inets already uninit for stop command");
				inited ->
					inets:stop();
				_ ->
					common:logerror("HTTP GPS inets unknwon state for stop command")
			end;
		{Pid, get} ->
			Pid ! {InitialIPPort, State, Count, ACount, FCount, FACount},
			http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount);
		_ ->
			common:logerror("HTTP GPS process receive unknown msg."),
			http_gps_deamon(InitialIPPort, State, Count, ACount, FCount, FACount)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Body is a binary list
% Return binary address
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_full_address(Body) ->
	%common:loginfo("Body : ~p", [Body]),
	Province = get_province_name(Body),
	%common:loginfo("Province : ~p", [Province]),
	City = get_city_name(Body),
	%common:loginfo("City : ~p", [City]),
	District = get_district_name(Body),
	%common:loginfo("District : ~p", [District]),
	Road = get_road_name(Body),
	%common:loginfo("Road : ~p", [Road]),
	FullAddressBin = list_to_binary([Province, City, District, Road]),
	FullAddressBin.

get_province_name(Body) ->
	ProvinceBins = binary:split(Body, [<<"\"province\":{\"name\":\"">>], [global]),
	case length(ProvinceBins) of
		2 ->
			[_, ProvinceInfo] = ProvinceBins,
			ProvinceInfoBins = binary:split(ProvinceInfo, [<<"\",\"ename\":\"">>], [global]),
			Len = length(ProvinceInfoBins),
			if
				Len > 0 ->
					Province = lists:nth(1, ProvinceInfoBins),
					Province;
				true ->
					<<>>
			end;
		_ ->
			<<>>
	end.

get_city_name(Body) ->
	CityBins = binary:split(Body, [<<"\"city\":{\"citycode\":\"">>], [global]),
	case length(CityBins) of
		2 ->
			[_, CityInfo] = CityBins,
			CityInfoBins = binary:split(CityInfo, [<<"\"name\":\"">>, <<"\",\"ename\":\"">>], [global]),
			%common:loginfo("CityInfoBins : (~p)~n~p", [length(CityInfoBins), CityInfoBins]),
			Len = length(CityInfoBins),
			if
				Len > 1 ->
					City = lists:nth(2, CityInfoBins),
					City;
				true ->
					<<>>
			end;
		_ ->
			<<>>
	end.

get_district_name(Body) ->
	DistrictBins = binary:split(Body, [<<"\"district\":{\"name\":\"">>], [global]),
	case length(DistrictBins) of
		2 ->
			[_, DistrictInfo] = DistrictBins,
			DistrictInfoBins = binary:split(DistrictInfo, [<<"\",\"ename\":\"">>], [global]),
			Len = length(DistrictInfoBins),
			if
				Len > 0 ->
					Dictrict = lists:nth(1, DistrictInfoBins),
					Dictrict;
				true ->
					<<>>
			end;
		_ ->
			<<>>
	end.

get_road_name(Body) ->
	RoadBins = binary:split(Body, [<<"\"roadlist\":[{\"id\":\"">>], [global]),
	case length(RoadBins) of
		2 ->
			[_, RoadInfo] = RoadBins,
			RoadInfoBins = binary:split(RoadInfo, [<<"\"name\":\"">>, <<"\",\"ename\":\"">>], [global]),
			%common:loginfo("RoadInfoBins : (~p)~n~p", [length(RoadInfoBins), RoadInfoBins]),
			Len = length(RoadInfoBins),
			if
				Len > 1 ->
					Road = lists:nth(2, RoadInfoBins),
					Road;
				true ->
					<<>>
			end;
		_ ->
			<<>>
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Lon : Jingdu
% Lat : Weidu
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
convertrequest(Request) when is_list(Request),
							 length(Request) == 2 ->
	[Lon, Lat] = Request,
	SLon = erlang:float_to_list(Lon, [{decimals, 6}, compact]),
	SLat = erlang:float_to_list(Lat, [{decimals, 6}, compact]),
	{ok, lists:append([SLon, ",", SLat])};
convertrequest(_Request) ->
	error.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% File END.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

