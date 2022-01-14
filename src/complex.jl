"""
    Stateful{T, S}
    Stateful(schedule::T; advance = state -> true)

Create a stateful iterator around `schedule`.
Pass in a predicate, `advance(state)`, to conditionally control iteration.
See also [`ParameterSchedulers.next!`](#) and [`ParameterSchedulers.reset!`](#).
"""
mutable struct Stateful{T, S<:Integer, R}
    schedule::T
    state::S
    advance::R
end
Stateful(schedule; advance = state -> true) = Stateful(schedule, 1, advance)

"""
    next!(iter::Stateful)

Advance `iter` by one iteration
(if `iter.advance(state) == true`) and return the next value.
See also [`ParameterSchedulers.Stateful`](#).
"""
function next!(iter::Stateful)
    val = iter.schedule(iter.state)
    if iter.advance(iter.state)
        iter.state += 1
    end

    return val
end

"""
    reset!(iter::Stateful)

Reset `iter` to its initial state.
See also [`ParameterSchedulers.Stateful`](#).
"""
function reset!(iter::Stateful)
    iter.state = 1

    return iter
end

"""
    Constant{T}
    Constant(value)

A constant schedule that is always `value`.
"""
struct Constant{T}
    value::T
end

(schedule::Constant)(t) = schedule.value

Base.eltype(::Type{<:Constant{T}}) where T = T
Base.IteratorSize(::Type{<:Constant}) = Base.IsInfinite()

Base.iterate(schedule::Constant, t = 1) = schedule(t), t + 1

"""
    Sequence{T, S}
    Sequence(schedules, step_sizes)
    Sequence(schedule1 => step1, schedule2 => step2, ...)

A sequence of schedules.
The output of this schedule is the concatenation of `schedules` where each
schedule is evaluated for each step size in `step_sizes`.

Note that `schedules` can also be a vector of numbers (not just schedules).

# Arguments
- `schedules`: a vector of schedules or numbers
- `step_sizes`: a vector of iteration lengths for each schedule
"""
struct Sequence{T, S}
    schedules::T
    step_sizes::S

    function Sequence(schedules, step_sizes)
        _schedules = map(s -> s isa Number ? Constant(s) : s, schedules)

        new{typeof(_schedules), typeof(step_sizes)}(_schedules, step_sizes)
    end
end
Sequence(stages::Pair...) = Sequence(first.(stages), last.(stages))

function (schedule::Sequence)(t)
    accum_steps = cumsum(schedule.step_sizes)
    i = findlast(x -> t > x, accum_steps)
    i = isnothing(i) ? 1 :
            (i >= length(schedule.schedules)) ? length(schedule.schedules) : i + 1
    toffset = (i > 1) ? t - accum_steps[i - 1] : t

    return schedule.schedules[i](toffset)
end

Base.IteratorEltype(::Type{<:Sequence}) = Base.EltypeUnknown()
Base.IteratorSize(::Type{<:Sequence}) = Base.SizeUnknown()

function Base.iterate(schedule::Sequence, state = (1, 1, 1))
    t, i, t0 = state
    if (i < length(schedule.step_sizes)) && (t >= t0 + schedule.step_sizes[i])
        # move onto next step range
        i += 1
        t0 = t
    end

    return schedule.schedules[i](t - t0 + 1), (t + 1, i, t0)
end

"""
    Loop{T, S<:Integer}
    Loop(f, period)

Create a schedule that loops `f` every `period` iterations.
`f` must be callabe (a function or schedule).

# Arguments
- `f`: the schedule to loop
- `period::Integer`: how often to loop
"""
struct Loop{T, S<:Integer}
    f::T
    period::S
end
Loop(f, period) = Loop(f, period)

(schedule::Loop)(t) = schedule.f(mod1(t, schedule.period))

Base.IteratorEltype(::Type{<:Loop{T}}) where T = Base.IteratorEltype(T)
Base.eltype(::Type{<:Loop{T}}) where T = eltype(T)
Base.IteratorSize(::Type{<:Loop}) = Base.IsInfinite()

Base.iterate(schedule::Loop, t = 1) = schedule(t), t + 1

Base.axes(::Loop) = (OneToInf(),)

"""
    Interpolator{T, S}
    Interpolator(schedule, rate)

A schedule whose output is `schedule(t / rate)` (i.e. it interpolates `schedule(t)`).

This can be useful when your code iterates over real numbers at a fixed rate
(e.g. in a fixed time step differential solver),
but you want to use a schedule that iterates discretely over integers.

It could also be used to specify `schedule` in units of epochs,
while iterating it in units of mini-batches.
"""
struct Interpolator{T, S}
    schedule::T
    rate::S
end

(interpolator::Interpolator)(t) = interpolator.schedule(t / interpolator.rate)

Base.eltype(::Type{<:Interpolator{T}}) where T = eltype(T)
Base.IteratorEltype(::Type{<:Interpolator{T}}) where T = Base.IteratorEltype(T)
Base.IteratorSize(::Type{<:Interpolator{T}}) where T = Base.IteratorSize(T)

Base.iterate(interpolator::Interpolator, t = 1) = interpolator(t), t + 1

"""
    reverse(f, period)

Return a reverse function such that `reverse(f, period)(t) == f(period - t)`.
"""
reverse(f, period) = t -> f(period - t)
"""
    symmetric(f, period)

Return a symmetric function such that for `t ∈ [1, period / 2)`,
the symmetric function evaluates to `f(t)`, and when `t ∈ [period / 2, period)`,
the symmetric functions evaluates to `f(period - t)`.
"""
symmetric(f, period) = t -> (t < period / 2) ? f(t) : f(period - t)
