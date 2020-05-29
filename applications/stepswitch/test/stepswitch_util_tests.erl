%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(stepswitch_util_tests).

-include_lib("eunit/include/eunit.hrl").
-include("stepswitch.hrl").

%%%=============================================================================
%%% Fixtures
%%%=============================================================================
shortdial_correction_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun (SetupsReturn) ->
             {'inorder'
             ,[maybe_constrain_shortdial_correction(SetupsReturn)
              ,shortdial_correction_length(SetupsReturn)
              ,maybe_deny_reclassified_number(SetupsReturn)
              ,do_correct_shortdial(SetupsReturn)
              ]
             }
     end
    }.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
setup() ->
    meck:new('kapps_config', ['unstick', 'passthrough']).

cleanup(_) ->
    meck:unload('kapps_config').

%%%=============================================================================
%%% Tests
%%%=============================================================================
maybe_constrain_shortdial_correction(_) ->
    Test = fun stepswitch_util:maybe_constrain_shortdial_correction/1,
    F = fun(?SS_CONFIG_CAT, <<"max_shortdial_correction">>, _) -> 4;
           (?SS_CONFIG_CAT, <<"min_shortdial_correction">>, _) -> 2
        end,
    meck:expect('kapps_config', 'get_integer', F),

    [{"If Length is within bounds (included), return Length"
     ,[?_assertEqual(4, Test(4))
      ,?_assertEqual(3, Test(3))
      ,?_assertEqual(2, Test(2))
      ]
     }
    ,{"If Length is out of bounds, return 0 (zero)"
     ,[?_assertEqual(0, Test(10))
      ,?_assertEqual(0, Test(5))
      ,?_assertEqual(0, Test(1))
      ]
     }
    ].

shortdial_correction_length(_) ->
    Test = fun stepswitch_util:shortdial_correction_length/2,
    Fixed = fun(Return) -> fun(?SS_CONFIG_CAT, <<"fixed_length_shortdial_correction">>) -> Return end end,
    MinMax = fun(?SS_CONFIG_CAT, <<"max_shortdial_correction">>, _) -> 4;
                (?SS_CONFIG_CAT, <<"min_shortdial_correction">>, _) -> 2
             end,
    meck:expect('kapps_config', 'get_integer', MinMax),

    meck:expect('kapps_config', 'get_integer', Fixed('undefined')),
    Resp1 = Test(<<"12345">>, <<"1234567">>),
    Resp2 = Test(<<"123">>, <<"1234567">>),
    Resp3 = Test(<<"123">>, <<"12345678">>), %% Difference = 5
    Resp4 = Test(<<"123">>, <<"1234">>), %% Difference = 1

    FixedLength = 4,
    meck:expect('kapps_config', 'get_integer', Fixed(FixedLength)),
    Resp5 = Test(<<"12345">>, <<"1234567">>),
    Resp6 = Test(<<"123">>, <<"1234567">>),

    [{"If fixed is undefined, return calculated length if it is within bounds, 0 (zero) otherwise"
     ,[?_assertEqual(2, Resp1)
      ,?_assertEqual(4, Resp2)
      ,?_assertEqual(0, Resp3)
      ,?_assertEqual(0, Resp4)
      ]
     }
    ,{"If fixed is defined, return its value"
     ,[?_assertEqual(FixedLength, Resp5)
      ,?_assertEqual(FixedLength, Resp6)
      ]
     }
    ].

maybe_deny_reclassified_number(_) ->
    Test = fun stepswitch_util:maybe_deny_reclassified_number/3,
    CorrectedNumber = <<"1234567">>,
    CallRestrictions = kz_json:from_list_recursive([{<<"unknown">>, [{<<"action">>, <<"deny">>}]}]),

    meck:new('knm_converters', ['passthrough']),
    meck:expect('knm_converters', 'classify', fun(_) -> <<"unknown">> end), %% Just to be sure ;)
    Resp1 = Test(CorrectedNumber, <<"1234">>, CallRestrictions),
    Resp2 = Test(CorrectedNumber, <<"7654321">>, CallRestrictions),
    meck:unload('knm_converters'),

    [{"If not Call Restrictions, return the corrected number"
     ,[?_assertEqual(CorrectedNumber, Test(CorrectedNumber, <<"1234">>, kz_json:new()))
      ,?_assertEqual(CorrectedNumber, Test(CorrectedNumber, <<"7654321">>, kz_json:new()))
      ]
     }
    ,{"If Call Restrictions apply, return undefined"
      ,[?_assertEqual('undefined', Resp1)
      ,?_assertEqual('undefined', Resp2)
      ]
     }
    ].

do_correct_shortdial(_) ->
    Test = fun stepswitch_util:do_correct_shortdial/3,
    CallerNumber = <<"12223334444">>,
    CalleeNumber = <<"3335555">>,

    [{"Take up to Length digits from CallerNumber and prefix CalleeNumber with those digits"
     ,[?_assertEqual(<<"3335555">>, Test(CalleeNumber, CallerNumber, 0))
      ,?_assertEqual(<<"123335555">>, Test(CalleeNumber, CallerNumber, 2))
      ,?_assertEqual(<<"+12223335555">>, Test(CalleeNumber, CallerNumber, 4))
      ,?_assertEqual(<<CallerNumber/binary, CalleeNumber/binary>>
                    ,Test(CalleeNumber, CallerNumber, byte_size(CallerNumber) + 1)
                    )
      ]
     }
    ].

should_correct_shortdial_test_() ->
    Test = fun stepswitch_util:should_correct_shortdial/1,
    Number = <<"3335555">>,

    meck:new('kapps_config', ['unstick', 'passthrough']),
    F = fun(Return) ->
                fun(?SS_CONFIG_CAT, <<"shortdial_correction_if_length_is">>, 0) -> Return end %% Just to be sure
        end,

    meck:expect('kapps_config', 'get_integer', F(0)),
    Resp1 = Test(Number),

    Length1 = byte_size(Number) + 1,
    meck:expect('kapps_config', 'get_integer', F(Length1)),
    Resp2 = Test(Number),
    Resp3 = Test(kz_binary:truncate(Number, 5)),

    Length2 = byte_size(Number),
    meck:expect('kapps_config', 'get_integer', F(Length2)),
    Resp4 = Test(Number),

    Tests =
    [{"If length_is is equal to 0 (zero), return {true, 0}"
     ,?_assertEqual({'true', 0}, Resp1)
     }
    ,{"If length_is is greater than 0 (zero) and doesn't match dialed number's length, return {false, Length}"
     ,[?_assertEqual({'false', Length1}, Resp2)
      ,?_assertEqual({'false', Length1}, Resp3)
      ]
     }
    ,{"If length_is is greater than 0 (zero) and matches dialed number's length, return {true, Length}"
     ,?_assertEqual({'true', Length2}, Resp4)
     }
    ],
    meck:unload('kapps_config'),
    Tests.

correct_shortdial_test_() ->
    Test = fun stepswitch_util:correct_shortdial/4,
    %% length(CallerNumber) - length(CalleeNumber) = 4
    CallerNumber = <<"12223334444">>,
    CalleeNumber = <<"3335555">>,
    CallRestrictions = kz_json:from_list_recursive([{<<"unknown">>, [{<<"action">>, <<"deny">>}]}]),

    meck:new('kapps_config', ['unstick', 'passthrough']),
    meck:new('knm_converters', ['passthrough']),

    MinMax = fun(Min, Max) ->
                fun(?SS_CONFIG_CAT, <<"max_shortdial_correction">>, _) -> Max;
                   (?SS_CONFIG_CAT, <<"min_shortdial_correction">>, _) -> Min
                end
        end,
    Fixed = fun(L) -> fun(?SS_CONFIG_CAT, <<"fixed_length_shortdial_correction">>) -> L end end,

    meck:expect('kapps_config', 'get_integer', MinMax(2, 5)),
    meck:expect('kapps_config', 'get_integer', Fixed('undefined')),
    %% min=2, max=5, fixed=undefined, length=automatically-calculated
    Resp1 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    meck:expect('kapps_config', 'get_integer', Fixed(4)),
    %% min=2, max=5, fixed=4, length=4
    Resp2 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    meck:expect('kapps_config', 'get_integer', Fixed(3)),
    %% min=2, max=5, fixed=3, length=3
    Resp3 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    meck:expect('kapps_config', 'get_integer', MinMax(1, 3)),
    meck:expect('kapps_config', 'get_integer', Fixed('undefined')),
    %% min=1, max=3, fixed=undefined length=automatically-calculated
    Resp4 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    meck:expect('kapps_config', 'get_integer', MinMax(5, 8)),
    %% min=5, max=8, fixed=undefined, length=automatically-calculated
    Resp5 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    meck:expect('knm_converters', 'classify', fun(_) -> <<"unknown">> end), %% Just to be sure ;)
    %% min=5, max=8, fixed=undefined, length=automatically-calculated
    Resp6 = Test(CalleeNumber, CallerNumber, CallRestrictions, {'true', 0}),

    meck:expect('kapps_config', 'get_integer', Fixed(3)),
    %% min=5, max=8, fixed=3, length=3
    Resp7 = Test(CalleeNumber, CallerNumber, CallRestrictions, {'true', 0}),

    meck:expect('kapps_config', 'get_integer', Fixed(0)),
    %% min=5, max=8, fixed=0, length=0
    Resp8 = Test(CalleeNumber, CallerNumber, kz_json:new(), {'true', 0}),

    Tests =
    [{"If length_is is 'disabled', no call restrictions, and calculated length is between bounds or fixed is defined, return corrected number"
     ,[?_assertEqual(<<"+12223335555">>, Resp1)
      ,?_assertEqual(<<"+12223335555">>, Resp2)
      ,?_assertEqual(<<"1223335555">>, Resp3)
      ]
     }
    ,{"If fixed and length_is are 'disabled', no call restrictions, and calculated length is outside bounds, return undefined"
     ,[?_assertEqual('undefined', Resp4)
      ,?_assertEqual('undefined', Resp5)
      ]
     }
    ,{"If length_is is disabled, calculated length is between bounds or fixed is defined, but call restrictions apply, return undefined"
     ,[?_assertEqual('undefined', Resp6)
      ,?_assertEqual('undefined', Resp7)
      ]
     }
    ,{"If length_is is disabled, no call restrictions, and fixed value is 0 (zero), return undefined"
     ,?_assertEqual('undefined', Resp8)
     }
    ,{"If length_is is defined and CalleeNumber's length doesn't match it, return undefined"
     ,[?_assertEqual('undefined'
                    ,Test(CalleeNumber, CallerNumber, kz_json:new(), {'false', byte_size(CalleeNumber) + 1})
                    )
      ,?_assertEqual('undefined'
                    ,Test(CalleeNumber, CallerNumber, kz_json:new(), {'false', byte_size(CalleeNumber) - 1})
                    )
      ]
     }
    ],

    meck:unload('knm_converters'),
    meck:unload('kapps_config'),
    Tests.
