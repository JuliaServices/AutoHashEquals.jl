"""
    type_seed(x)

Computes a value to use as a seed for computing the hash value of a type.

The constants used in this computation are random numbers
produced by `Random.rand(Random.RandomDevice(), UInt)`.
"""
function type_seed end

function type_seed(m::Module, h::UInt)
    if m === Main || m === Base || m === Core
        return h
    else
        mp = parentmodule(m)
        if mp === m
            return h
        else
            return type_seed(nameof(m), type_seed(mp, h))
        end
    end
end

function type_seed(t::UnionAll, h::UInt)
    h = hash(h, 0xbd5f3e4941dba79d)
    h = type_seed(t.var, h)
    h = type_seed(t.body, h)
    return h
end

function type_seed(x::Union, h::UInt)
    h = hash(h, 0xa16a31201c4852c2)
    for t in Base.uniontypes(x)
        h = type_seed(t, h)
    end
    return h
end

function type_seed(t::TypeVar, h::UInt)
    h = hash(h, 0xc921c42a65aee273)
    h = type_seed(t.name, h)
    h = type_seed(t.lb, h)
    h = type_seed(t.ub, h)
    return h
end

function type_seed(t::DataType, h::UInt)
    h = hash(h, 0x5e90a8c7e280e39b)
    tn = t.name
    if (isdefined(tn, :module))
        h0 = 0xae72cbeead1b2d46
        h0 = type_seed(tn.module, h0)
        h = hash(h, h0)
    end
    h = type_seed(tn.name, h)
    if !isempty(t.parameters)
        h0 = 0x9f86d3fbe4382c06
        for p in t.parameters
            h0 = type_seed(p, h0)
        end
        h = hash(h, h0)
    end
    return h
end

function type_seed(t::Core.TypeofBottom, h::UInt)
    return hash(h, 0x68f57dd85252e163)
end

#
# The following two meta-types changed representation in 1.7, so we are
# explicit about their hashes to ensure stability from 1.6 to 1.7.
#
type_seed(::Type{NTuple}, h::UInt) = 0x789db08b2c84bf6c
type_seed(::Type{Tuple}, h::UInt) = 0x571b7e681184913a

#
# For non-type values (e.g. `x` in `Val{x}`) we delegate to Base.hash.
# Note, however, that Julia 1.7 changed the implementation of Base.hash(::Symbol, ::UInt),
# yet retained stability of `Base.hash(::Symbol)`.   We take advantage of that to make
# the type seed computation stable even back to Julia 1.6 for types whose hashes are
# unstable in that way.
#
type_seed(x, h::UInt) = Base.hash(Base.hash(x), h)

type_seed(x) = type_seed(x, UInt(0))
