VERSION < v"0.7.0-beta2.199" && __precompile__(true)

module AutoHashEquals

export @auto_hash_equals


function auto_hash(name, names)

    function expand(i)
        if i == 0
            :(hash($(QuoteNode(name)), h))
        else
            :(hash(a.$(names[i]), $(expand(i-1))))
        end
    end

    quote
        function Base.hash(a::$(name), h::UInt)
            $(expand(length(names)))
        end
    end
end

function auto_equals(name, names)

    function expand(i)
        if i == 0
            :true
        else
            :(isequal(a.$(names[i]), b.$(names[i])) && $(expand(i-1)))
        end
    end

    quote
        function Base.:(==)(a::$(name), b::$(name))
            $(expand(length(names)))
        end
    end
end

struct UnpackException <: Exception
    msg
end

unpack_name(node::Symbol) = node

function unpack_name(node::Expr)
    if node.head == :macrocall
        unpack_name(node.args[2])
    else
        i = node.head == :type || node.head == :struct ? 2 : 1   # skip mutable flag
        if length(node.args) >= i && isa(node.args[i], Symbol)
            node.args[i]
        elseif length(node.args) >= i && isa(node.args[i], Expr) && node.args[i].head in (:(<:), :(::))
            unpack_name(node.args[i].args[1])
        elseif length(node.args) >= i && isa(node.args[i], Expr) && node.args[i].head == :curly
            unpack_name(node.args[i].args[1])
        else
            throw(UnpackException("cannot find name in $(node)"))
        end
    end
end


macro auto_hash_equals(typ)

    @assert typ.head == :type || typ.head == :struct
    name = unpack_name(typ)

    names = Vector{Symbol}()
    for field in typ.args[3].args
        try
            push!(names, unpack_name(field))
        catch ParseException
            # not a field
        end
    end

    quote
        Base.@__doc__($(esc(typ)))
        $(esc(auto_hash(name, names)))
        $(esc(auto_equals(name, names)))
    end
end


end
