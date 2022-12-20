using Dates

"""
Returns true if datetime t is start of iso year
"""
isisoyearstart(t::DateTime) = (week(t) == 1) && (dayofweek(t) == 1) && (Time(t) == Time(0))


"""
Get datetime that is start of iso year
"""
getisoyearstart(t::DateTime) = DateTime(Date(t + Day(8 - 7*week(t) - dayofweek(t))))
getisoyearstart(isoyear::Int) = getisoyearstart(DateTime(isoyear, 5, 1))

"""
Get iso year of a datetime
"""
getisoyear(t::DateTime) = year(t + Week(15 - week(t)))


"""
Get datetime for isoyear that is similar iso time of year as input datetime t
"""
function getsimilardatetime(t::DateTime, isoyear::Int)
    DateTime(Date(getisoyearstart(isoyear) + Day(7*week(t) + dayofweek(t) - 8)), Time(t))
end