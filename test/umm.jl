using TuLiPa, JSON, Dates, Test


horizon = SequentialHorizon(40, Day(1))
obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"), UMMSeriesParam(
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00"),
            ],
            [1, 1, 1]),  # level
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")
            ],
            [1, 0.5, 0.5]), # umm profile
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")
            ],
            [10, 10, 10])), true) # profile

#using umm profile, 1 day delta and 1 hour offset from inf time vector datetimes:  (23/24)*1 + (1/24)*0.5
pt = TwoTime(DateTime("2023-01-01T01:00:00"), DateTime("2023-01-01T01:00:00"))
querystart = getstarttime(horizon, 1, pt)
querydelta = gettimedelta(horizon, 1)
@test getparamvalue(obj_test.param, querystart, querydelta) == 0.9791666666666666

#using mix of ummprofile and profile (23/24)*0.5 + (1/24)*10
querystart = getstarttime(horizon, 2, pt)
querydelta = gettimedelta(horizon, 2)
@test getparamvalue(obj_test.param, querystart, querydelta) == 0.8958333333333333

#using only profile 
querystart = getstarttime(horizon, 3, pt)
querydelta = gettimedelta(horizon, 3)
@test getparamvalue(obj_test.param, querystart, querydelta) == 10

obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"),
    UMMSeriesParam(
        InfiniteTimeVector(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")],
            [1, 1, 1]),  # level
        InfiniteTimeVector(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")],
            [1, 0.5, 0.5]), # umm profile
        InfiniteTimeVector(
            [DateTime("1980-01-01T00:00:00"),
                DateTime("1980-01-02T00:00:00"),
                DateTime("1980-01-03T00:00:00"),
            ],
            [1, 2, 3]) # profile
    ), true)

pt = TwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T12:00:00"))
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
datatime = getdatatime(querystart)
scenariotime = getscenariotime(querystart)

# Check that the new start time for profile is correct.
# Should use the last umm date as starting point.
# Last umm date is 2023-01-03
# In scenario time this is 1980-01-03
@test TuLiPa._get_new_profile_start(obj_test.param, datatime, scenariotime)[1] == DateTime("1980-01-03T00:00:00")

pt = TwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T00:00:00"))
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
datatime = getdatatime(querystart)
scenariotime = getscenariotime(querystart)

# Datatime and scenario datime is not alligned 01-01T12 and 01-01T00.
# New start time will then be different than the last umm date.
# Last umm date is 2023-01-03 or 1 day and 12 hours away from datatime start.
# New scenario time will then be 1980-01-01T00:00:00 + 1 day and 12 hours = 1980-01-02T12
@test TuLiPa._get_new_profile_start(obj_test.param, datatime, scenariotime)[1] == DateTime("1980-01-02T12:00:00")

obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"),
    UMMSeriesParam(
        InfiniteTimeVector(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")],
            [1, 1, 1]),  # level
        InfiniteTimeVector(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")],
            [1, 0.5, 0.5]), # umm profile
        InfiniteTimeVector(
            [DateTime("1980-01-01T00:00:00"),
                DateTime("1980-01-02T00:00:00"),
                DateTime("1980-01-03T00:00:00"),
                DateTime("1985-01-01T00:00:00") # 1985 value used by scenariotime2 phasein
            ],
            [1, 2, 3, 0]) # profile
    ), true)

phaseinvector = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
    [DateTime("1980-01-01T00:00:00"),
        DateTime("1980-01-02T00:00:00"),
        DateTime("1980-01-03T00:00:00")
    ],
    [0, 0, 1])

pt = PhaseinTwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T12:00:00"), DateTime("1985-01-01T12:00:00"), phaseinvector)
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)

datatime = getdatatime(querystart)
scenariotime = getscenariotime(querystart)

# Phasetime date (scenariotime2) is used at period t = 2 so
# The difference between datatime 2023-01-01T12 and last umm date 2023-01-03T00 is 1 day and 12 hours
# so the new profile time will be 1985-01-01T12 + 1 day and 12 hours = 1985-01-03T00
@test TuLiPa._get_new_profile_start(obj_test.param, datatime, scenariotime)[1] == DateTime("1985-01-03T00:00:00")

phaseinvector = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
    [DateTime("1980-01-01T00:00:00"),
        DateTime("1980-01-02T00:00:00"),
        DateTime("1980-01-03T00:00:00")
    ],
    [0, 0, 0.5])

pt = PhaseinTwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T12:00:00"), DateTime("1985-01-01T12:00:00"), phaseinvector)
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)

# Phase in scenariotime2 values by 0.5 into profile 0.5 * 0 + 0.5 * 3
# half umm value and half profile value 0.5*0.5 + 0.5( ... )
@test getparamvalue(obj_test.param, querystart, querydelta) == 1.0 # 0.5*0.5 + 0.5( 0.5 * 0 + 0.5 * 3)

phaseinvector = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
    [DateTime("1980-01-01T00:00:00"),
        DateTime("1980-01-02T00:00:00"),
        DateTime("1980-01-03T00:00:00")
    ],
    [0, 0, 0.5])

pt = PhaseinTwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T12:00:00"), DateTime("1985-01-01T00:00:00"), phaseinvector)
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
datatime = getdatatime(querystart)
scenariotime = getscenariotime(querystart)

# Scenariotime2 starts at 1985-01-01T00 and is not alligned with the rest of the datetimes.
# New start time will then be different than the last umm date.
@test TuLiPa._get_new_profile_start(obj_test.param, datatime, scenariotime)[1] == DateTime("1985-01-02T12:00:00")

# Fixed datatime

obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"), UMMSeriesParam(
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00"),
            ],
            [1, 1, 1]),  # level
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")
            ],
            [1, 0.5, 0.5]), # umm profile
        InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
            [DateTime("2023-01-01T00:00:00"),
                DateTime("2023-01-02T00:00:00"),
                DateTime("2023-01-03T00:00:00")
            ],
            [1, 1, 1])), true) # profile

horizon = SequentialHorizon(40, Day(1))
pt = FixedDataTwoTime(DateTime("2023-01-01T00:00:00"), DateTime("2023-01-01T00:00:00"))
t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)

# Because fixedDataTwoTime never changes the datatime, 
# then umm will never change, umm uses datatime
@test getparamvalue(obj_test.param, querystart, querydelta) == 1

phaseinvector = InfiniteTimeVector{Vector{DateTime},Vector{Float64}}(
    [DateTime("1980-01-01T00:00:00"),
        DateTime("1980-01-02T00:00:00"),
        DateTime("1980-01-03T00:00:00")
    ],
    [0, 0, 0.5])

pt = PhaseinFixedDataTwoTime(DateTime("2023-01-01T12:00:00"), DateTime("1980-01-01T12:00:00"), DateTime("1985-01-01T12:00:00"), phaseinvector)
horizon = SequentialHorizon(40, Day(1))
t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)

# datatime is constant 2023-01-01T12 meaning (0.5*1 + 0.5*0.5) = 0.75
# profile is: phasein 0.5*1 + 0.5*1 = 1
# but output will be using datatime so only umm time wil be used. 
@test getparamvalue(obj_test.param, querystart, querydelta) == 0.75
