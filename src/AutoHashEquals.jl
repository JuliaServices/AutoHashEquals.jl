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

struct_from_doc_struct_block(_e, _m) = nothing
function struct_from_doc_struct_block(e::Expr, meta_idx)
    i = meta_idx
    if length(e.args) >= i+1 && e.args[i+1] isa Expr && e.args[i+1].head == :struct
        return e.args[i+1]
    elseif length(e.args) >= i+2 && e.args[i+2] isa Expr && e.args[i+2].head == :struct
        return e.args[i+2]
    end
    return nothing
end

find_doc_struct_block(e) = nothing
function find_doc_struct_block(e::Expr)
    if e.head == :block
        for (i,arg) in enumerate(e.args)
            if arg == :($(Expr(:meta, :doc)))
                s = struct_from_doc_struct_block(e, i)
                # There can only be one @doc expression in a block, so if this
                # isn't the struct, there won't be one.
                return s  # might be nothing
            else
                s = find_doc_struct_block(arg)
                if s != nothing
                    return s
                end
            end
        end
    end
    return nothing
end

macro auto_hash_equals(typ)
    typ.head == :macrocall && (typ = Base.macroexpand(__module__, typ))

    orig_typ = typ
    
    if typ.head == :block
        typ = find_doc_struct_block(typ)
    end

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
    @assert length(names) > 0

    quote
        Base.@__doc__($(esc(orig_typ)))
        $(esc(auto_hash(name, names)))
        $(esc(auto_equals(name, names)))
    end
end


end
