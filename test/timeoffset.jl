using Dates, TuLiPa


datayear = 2021
scenarioyearstart = 1981
td = MsTimeDelta(Millisecond(24 * 10 * 60 * 60 * 1000))
td1 = MsTimeDelta(Millisecond(24 * 10 * 60 * 60 * 1000))
td2 = MsTimeDelta(Millisecond(24 * 5 * 60 * 60 * 1000))
dt1 = DateTime(2021, 1, 1, 0)
dt2 = DateTime(2021, 1, 1, 0);
phaseinoffsetdays = 2
phaseinoffset = Millisecond(Day(phaseinoffsetdays))
phaseindelta = Millisecond(Day(5))
phaseinsteps = 5;

prob_time = ConstantTime()
td_offset = TimeDeltaOffset(td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.value == DateTime("2022-10-07T00:00:00")

prob_time = FixedDataTwoTime(dt1, dt2)
td_offset = TimeDeltaOffset(td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime == DateTime("2021-01-11T00:00:00")

prob_time = TwoTime(dt1, dt2)
td_offset = TimeDeltaOffset(td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime == DateTime("2021-01-11T00:00:00")

prob_time = FixedDataTwoTime(dt1, dt2)
td_offset = ScenarioOffset(td1, td2)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime == DateTime("2021-01-16T00:00:00")

prob_time = TwoTime(dt1, dt2)
td_offset = ScenarioOffset(td1, td2)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime == DateTime("2021-01-16T00:00:00")

prob_time = FixedDataTwoTime(dt1, dt2)
td_offset = IsoYearOffset(1900, td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime == DateTime("1901-01-14T00:00:00")

prob_time = TwoTime(dt1, dt2)
td_offset = IsoYearOffset(1900, td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime == DateTime("1901-01-14T00:00:00")

prob_time = PhaseinTwoTime(dt1, dt2, dt2, phaseinoffset, phaseindelta, phaseinsteps)
td_offset = TimeDeltaOffset(td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("2021-01-11T00:00:00")

td_offset = IsoYearOffset(1900, td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("1901-01-14T00:00:00")

td_offset = ScenarioOffset(td1, td2)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("2021-01-16T00:00:00")

prob_time = PhaseinFixedDataTwoTime(dt1, dt2, dt2, phaseinoffset, phaseindelta, phaseinsteps)
td_offset = TimeDeltaOffset(td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("2021-01-11T00:00:00")

td_offset = IsoYearOffset(1900, td)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("1901-01-14T00:00:00")

td_offset = ScenarioOffset(td1, td2)
offset_time = getoffsettime(prob_time, td_offset)
@test offset_time.datatime == DateTime("2021-01-01T00:00:00")
@test offset_time.scenariotime1 == DateTime("2021-01-11T00:00:00")
@test offset_time.scenariotime2 == DateTime("2021-01-16T00:00:00")


# Even if PhaseinTwoTime is created with the same sceneraio twice, interpolation 
# between them can still be done, using scenarioOffset or IsoYearOffset.
# Create mock data and test that phaseintwotime gives the same values.

values = Array([sin(x) + 1 for x in 1:17641])
values[1:8820] .*= 1.2
level = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}([DateTime("2021-01-04T00:00:00"), DateTime("2024-12-30T00:00:00")], [100.0, 100.0])
index = DateTime("1980-12-29T00:00:00"):Millisecond(3600000):DateTime("1983-01-03T00:00:00")
profile = RotatingTimeVector(index, values, DateTime("1980-12-29T00:00:00"), DateTime("1983-01-03T00:00:00"));
param = MWToGWhSeriesParam(level, profile)
rhsterm = BaseRHSTerm(Id("RHSTerm", "WindGER_test"), param, true)

function get_phaseintwotime_offset_value_samples(offset, scenario_dt1, scenario_dt2, rhsterm)
        weeks = 51
        dt = getisoyearstart(2023)
        phaseinoffsetdays = 7 * 11
        phaseinoffset = Millisecond(Day(phaseinoffsetdays))
        phaseindelta = Millisecond(Day(7 * 10))
        phaseinsteps = 7 * 10
        prob_time = PhaseinTwoTime(dt, scenario_dt1, scenario_dt2, phaseinoffset, phaseindelta, phaseinsteps)
        horizon_offset = SequentialHorizon(weeks, Week(1), offset=offset)

        querystart = getstarttime(horizon_offset, 1, prob_time)
        querydelta = gettimedelta(horizon_offset, 1)
        value_1 = getparamvalue(rhsterm, querystart, querydelta)

        querystart = getstarttime(horizon_offset, 15, prob_time)
        querydelta = gettimedelta(horizon_offset, 15)
        value_15 = getparamvalue(rhsterm, querystart, querydelta)

        querystart = getstarttime(horizon_offset, 25, prob_time)
        querydelta = gettimedelta(horizon_offset, 25)
        value_25 = getparamvalue(rhsterm, querystart, querydelta)
        return value_1, value_15, value_25
end

td2 = MsTimeDelta(getisoyearstart(1982) - getisoyearstart(1981))
td1 = MsTimeDelta(Millisecond(7 * 24 * 60 * 60 * 1000))

offset = IsoYearOffset(1982, td1)
IsoYearOffset_value_1, IsoYearOffset_value_15, IsoYearOffset_value_25 = get_phaseintwotime_offset_value_samples(offset, getisoyearstart(1981), getisoyearstart(1981), rhsterm)

offset = ScenarioOffset(td1, td2)
ScenarioOffset_value_1, ScenarioOffset_value_15, ScenarioOffset_value_25 = get_phaseintwotime_offset_value_samples(offset, getisoyearstart(1981), getisoyearstart(1981), rhsterm)

offset = TimeDeltaOffset(td1)
TimeDeltaOffset_value_1, TimeDeltaOffset_value_15, TimeDeltaOffset_value_25 = get_phaseintwotime_offset_value_samples(offset, getisoyearstart(1981), getisoyearstart(1982), rhsterm)

@test IsoYearOffset_value_1 == ScenarioOffset_value_1 == TimeDeltaOffset_value_1
@test IsoYearOffset_value_15 == ScenarioOffset_value_15 == TimeDeltaOffset_value_15
@test IsoYearOffset_value_25 == ScenarioOffset_value_25 == TimeDeltaOffset_value_25