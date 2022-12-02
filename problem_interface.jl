"""
General problem interface and fallback
"""

# General update function
function update!(p::Prob, start::ProbTime)
    for horizon in gethorizons(p)
        update!(horizon, start)
    end
    for obj in getobjects(p)
        update!(p, obj, start)
    end
end

# Fallbacks
notimplementederror() = error("Not implemented")

build!(::Prob, ::Any, ::ProbTime) = notimplementederror()

solve!(::Prob) = notimplementederror()

getobjects(::Prob) = notimplementederror()

setconstants!(::Prob, ::Any) = notimplementederror()

update!(::Prob, ::Any, ::ProbTime) = notimplementederror()

ismin(::Prob) = notimplementederror()

addvar!(::Prob, ::Id, ::Int) = notimplementederror()
addeq!(::Prob,  ::Id, ::Int) = notimplementederror()
addge!(::Prob,  ::Id, ::Int) = notimplementederror()
addle!(::Prob,  ::Id, ::Int) = notimplementederror()

setconcoeff!(::Prob, ::Id, ::Id, ::Int, ::Int, ::Float64) = notimplementederror()

setub!(::Prob, ::Id, ::Int, ::Float64) = notimplementederror()
setlb!(::Prob, ::Id, ::Int, ::Float64) = notimplementederror()

setobjcoeff!(::Prob, ::Id, ::Int, ::Float64) = notimplementederror()

setrhsterm!(::Prob, ::Id, ::Id, ::Int, ::Float64) = notimplementederror()

getconcoeff(::Prob, ::Id, ::Id, ::Int, ::Int) = notimplementederror()

getub(::Prob, ::Id, ::Int) = notimplementederror()
getlb(::Prob, ::Id, ::Int) = notimplementederror()

getobjcoeff(::Prob, ::Id, ::Int) = notimplementederror()

getrhsterm(::Prob, ::Id, ::Id, ::Int) = notimplementederror()

getobjectivevalue(::Prob) = notimplementederror()

getvarvalue(::Prob, ::Id, ::Int) = notimplementederror()

getcondual(::Prob, ::Id, ::Int) = notimplementederror()

setsilent!(::Prob) = notimplementederror()
unsetsilent!(::Prob) = notimplementederror()

# setpresolve!(::Prob) = notimplementederror()
# unsetpresolve!(::Prob) = notimplementederror()

# trybarrier!(::Prob) = notimplementederror()
# trybarriernocross!(::Prob) = notimplementederror()
# trydualsimplex!(::Prob) = notimplementederror()
# tryprimalsimplex!(::Prob) = notimplementederror()
# trynetwork!(::Prob) = notimplementederror()
