"""
    type_key(x)

Computes a value to use as a seed for computing the hash value of a type.
"""
function type_key end

function type_key(m::Module, h::UInt)
    if m === Main || m === Base || m === Core
        return h
    else
        mp = parentmodule(m)
        if mp === m
            return h
        else
            return hash(nameof(m), type_key(mp, h))
        end
    end
end

function type_key(t::UnionAll, h::UInt)
    h = hash(h, 0xbd5f3e4941dba79d)
    h = type_key(t.var, h)
    h = type_key(t.body, h)
    h
end

function type_key(x::Union, h::UInt)
    h = hash(h, 0xa16a31201c4852c2)
    for t in Base.uniontypes(x)
        h = type_key(t, h)
    end
    return h
end

function type_key(t::TypeVar, h::UInt)
    h = hash(h, 0xc921c42a65aee273)
    h = hash(t.name, h)
    h = type_key(t.lb, h)
    h = type_key(t.ub, h)
    return h
end

function type_key(t::DataType, h::UInt)
    h = hash(h, 0x5e90a8c7e280e39b)
    tn = t.name
    if (isdefined(tn, :module))
        h0 = 0xae72cbeead1b2d46
        h0 = type_key(tn.module, h0)
        h = hash(h, h0)
    end
    h = hash(tn.name, h)
    if !isempty(t.parameters)
        h0 = 0x9f86d3fbe4382c06
        for p in t.parameters
            h0 = type_key(p, h0)
        end
        h = hash(h, h0)
    end
    return h
end

function type_key(t::(typeof(Union{})), h::UInt)
    return hash(h, 0x68f57dd85252e163)
end

function type_key(t::Core.TypeofVararg, h::UInt)
    h = hash(h, 0xe7f2ebfee436674d)
    isdefined(t, :T) && (h = type_key(t.T, h))
    isdefined(t, :N) && (h = type_key(t.N, h))
    return h
end

type_key(x, h::UInt) = Base.hash(x, h)

type_key(x) = type_key(x, UInt(0))
