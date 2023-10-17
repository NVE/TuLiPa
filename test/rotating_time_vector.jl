using Dates, TuLiPa

# RotationTimeVector only rotate after a full year, not based on start stop dates.
obj_test = PositiveCapacity(Id("Capacity", "Capacity_test"),
        UMMSeriesParam(
                InfiniteTimeVector(
                        [DateTime("2023-01-01T00:00:00"),
                                DateTime("2023-01-02T00:00:00"),
                                DateTime("2023-01-03T00:00:00")],
                        [1, 1, 1]),  # level
                InfiniteTimeVector(
                        [DateTime("2023-01-01T00:00:00")],
                        [1]), # umm profile
                RotatingTimeVector(
                        [DateTime("1980-01-01T00:00:00"),
                                DateTime("1980-01-02T00:00:00"),
                                DateTime("1980-01-03T00:00:00")],
                        [0, 10, 0],  # profile
                        DateTime("1980-01-01T00:00:00"), #start
                        DateTime("1980-01-03T00:00:00")) #stop 
        ), true)

pt = TwoTime(DateTime("2023-01-01T00:00:00"), DateTime("1980-01-01T00:00:00"))
horizon = SequentialHorizon(700, Day(1))
t = 366
querystart = getstarttime(horizon, t, pt)
querydelta = gettimedelta(horizon, t)
getparamvalue(obj_test.param, querystart, querydelta) == 0.24