"""
    type_seed(x)

Computes a value to use as a seed for computing the hash value of a type.

The constants used in this computation are random.
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
            return hash(nameof(m), type_seed(mp, h))
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
    h = hash(t.name, h)
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
    h = hash(tn.name, h)
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

function type_seed(t::Core.TypeofVararg, h::UInt)
    h = hash(h, 0xe7f2ebfee436674d)
    isdefined(t, :T) && (h = type_seed(t.T, h))
    isdefined(t, :N) && (h = type_seed(t.N, h))
    return h
end

type_seed(x, h::UInt) = Base.hash(x, h)

type_seed(x) = type_seed(x, UInt(0))
