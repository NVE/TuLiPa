using Dates, TuLiPa

# RotationTimeVector only rotate after a full year, not based on start stop dates.
obj_test = 
        RotatingTimeVector(
            [DateTime("1980-01-01T00:00:00"), 
            DateTime("1980-01-02T00:00:00"),
            DateTime("1980-01-03T00:00:00")], 
            [0, 10, 5], 
            DateTime("1980-01-01T00:00:00"), #start
            DateTime("1980-01-04T00:00:00")) #stop 

pt = TwoTime(DateTime("2023-01-01T00:00:00"), DateTime("1980-01-01T00:00:00"))
horizon = SequentialHorizon(700, Day(1)) 

t = 1
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 0

t = 2
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 10

t = 3
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 5

# Same period as the stop value ("1980-01-04T00:00:00") gives 0.
t = 4
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 0

# After that repeats last value in the array.
t = 5
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 5

# After a year it will rotate.
t = 366
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
@test getweightedaverage(obj_test, querystart.scenariotime, querydelta) == 10