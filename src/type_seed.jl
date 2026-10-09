"""
    type_seed(x)

Computes a value to use as a seed for computing the hash value of a type.

Uses `Base.hash`; numeric results can change between Julia versions or processes.

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
# explicit about their seeds.
#
type_seed(::Type{NTuple}, h::UInt) = 0x789db08b2c84bf6c
type_seed(::Type{Tuple}, h::UInt) = 0x571b7e681184913a

#
# Walk tuple elements and named tuple field names explicitly.
#
function type_seed(t::Tuple, h::UInt)
    h = hash(h, 0x6ccd6cd06f6531b3)
    for e in t
        h = type_seed(e, h)
    end
    return h
end
function type_seed(t::NamedTuple, h::UInt)
    h = hash(h, 0x2014f9d53d478b4f)
    h = type_seed(fieldnames(typeof(t)), h)
    for e in t
        h = type_seed(e, h)
    end
    return h
end

#
# For non-type values (e.g. `x` in `Val{x}`) we delegate to Base.hash.
# The unseeded first hash avoids the Julia 1.7 change to the seeded Symbol hash.
# Results still depend on Base's hash algorithm and default seed.
#
type_seed(x, h::UInt) = Base.hash(Base.hash(x), h)

type_seed(x) = type_seed(x, UInt(0))
