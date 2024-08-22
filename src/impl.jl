const is_expr = Base.Meta.isexpr

function if_has_package(
    action::Function,
    name::String,
    uuid::Base.UUID,
    version::VersionNumber
)
    pkgid = Base.PkgId(uuid, name)
    if Base.root_module_exists(pkgid)
        pkg = Base.root_module(pkgid)
        if Base.pkgversion(pkg) >= version
            return action(pkg)
        end
    end
end

function error_usage(__source__, problem=nothing)
    if isnothing(problem)
        problem = ""
    end
    error("$(__source__.file):$(__source__.line): $problem  Usage:\n\n$(@doc AutoHashEquals.@auto_hash_equals)")
end

# `_show_default_auto_hash_equals_cached` is just like `Base._show_default(io, x)`,
# except it ignores fields named `_cached_hash`.  This function is called in the
# implementation of `T._show_default` for each type `T` annotated with
# `@auto_hash_equals cached=true`.  This is ultimately used in the implementation of
# `Base.show`.  This specialization ensures that showing circular data structures does not
# result in infinite recursion.
function _show_default_auto_hash_equals_cached(io::IO, @nospecialize(x))
    t = typeof(x)
    show(io, Base.inferencebarrier(t)::DataType)
    print(io, '(')
    recur_io = IOContext(io, Pair{Symbol,Any}(:SHOWN_SET, x),
                         Pair{Symbol,Any}(:typeinfo, Any))
    if !Base.show_circular(io, x)
        for i in 1:nfields(x)
            f = fieldname(t, i)
            if (f === :_cached_hash)
                continue
            elseif i > 1
                print(io, ", ")
            end
            isdefined(x, f) ? show(recur_io, getfield(x, i)) : print(io, Base.undef_ref_str)
        end
    end
    print(io,')')
end

# Find the first struct declaration buried in the Expr.
get_struct_decl(__source__, typ) = nothing
function get_struct_decl(__source__, typ::Expr)
    if typ.head === :struct
        return typ
    elseif typ.head === :macrocall
        return get_struct_decl(__source__, typ.args[3])
    end

    error_usage(__source__)
end

unpack_name(node) = node
function unpack_name(node::Expr)
    if node.head === :macrocall
        return unpack_name(node.args[3])
    elseif node.head in (:(<:), :(::))
        return unpack_name(node.args[1])
    else
        return node
    end
end

unpack_type_name(__source__, n::Symbol) = (n, n, nothing)
function unpack_type_name(__source__, n::Expr)
    if n.head === :curly
        type_name = n.args[1]
        type_name isa Symbol ||
            error_usage(__source__, "macro @auto_hash_equals applied to type with invalid signature: `$type_name`.")
        where_list = n.args[2:length(n.args)]
        type_params = map(unpack_name, where_list)
        full_type_name = Expr(:curly, type_name, type_params...)
        return (type_name, full_type_name, where_list)
    elseif n.head === :(<:)
        return unpack_type_name(__source__, n.args[1])
    else
        error_usage(__source__, "macro @auto_hash_equals applied to type with invalid signature: `$n`.")
    end
end

function get_fields(__source__, struct_decl::Expr; prevent_inner_constructors=false)
    member_names = Vector{Symbol}()
    member_decls = Vector()

    add_field(__source__, b) = nothing
    function add_field(__source__, b::Symbol)
        push!(member_names, b)
        push!(member_decls, b)
    end
    function add_field(__source__, b::Expr)
        if b.head === :block
            add_fields(__source__, b)
        elseif b.head === :const
            add_field(__source__, b.args[1])
        elseif b.head === :(::) && b.args[1] isa Symbol
            push!(member_names, b.args[1])
            push!(member_decls, b)
        elseif b.head === :macrocall
            add_field(__source__, b.args[3])
        elseif b.head === :function || b.head === :(=) && (b.args[1] isa Expr && b.args[1].head in (:call, :where))
            # :function, :equals:call, :equals:where are defining functions - inner constructors
            # we don't want to permit that if it would interfere with us producing them.
            prevent_inner_constructors &&
                error_usage(__source__, "macro @auto_hash_equals should not be used on a struct that declares an inner constructor.")
        end
    end
    function add_fields(__source__, b::Expr)
        @assert b.head === :block
        for field in b.args
            if field isa LineNumberNode
                __source__ = field
            else
                add_field(__source__, field)
            end
        end
    end

    @assert (struct_decl.args[3].head === :block)
    add_fields(__source__, struct_decl.args[3])
    return (member_names, member_decls)
end

function check_valid_alt_hash_name(__source__, alt_hash_name)
    isnothing(alt_hash_name) || alt_hash_name isa Symbol || is_expr(alt_hash_name, :.) ||
        error_usage(__source__, "invalid alternate hash function name: `$alt_hash_name`.")
end

isexpr(e, head) = e isa Expr && e.head == head
isexpr(e, head, n) = isexpr(e, head) && length(e.args) == n

function auto_hash_equals_impl(__source__::LineNumberNode, typ; kwargs...)
    # These are the default values of the keyword arguments
    cache=false
    hashfn=nothing
    fields=nothing
    typearg=false
    typeseed=nothing
    compat1=false

    # Process the keyword arguments
    for kw in kwargs
        @assert kw isa Pair
        @assert kw.first isa Symbol
        if kw.first === :cache
            if !(kw.second isa Bool)
                error_usage(__source__, "`cache` argument must be a Bool, but got `$(kw.second)`.")
            end
            cache = kw.second
        elseif kw.first === :typearg
            if !(kw.second isa Bool)
                error_usage(__source__, "`typearg` argument must be a Bool, but got `$(kw.second)`.")
            end
            typearg = kw.second
        elseif kw.first === :hashfn
            if !(kw.second isa Union{Symbol, Expr, Function})
                error_usage(__source__, "`hashfn` argument must name a function, but got `$(kw.second)`.")
            end
            hashfn = kw.second
            check_valid_alt_hash_name(__source__, hashfn)
        elseif kw.first === :fields
            if !(kw.second isa Tuple) || !all(f isa Symbol for f in kw.second)
                error_usage(__source__, "invalid `fields` argument: `$(kw.second)`.")
            end
            fields = kw.second
        elseif kw.first === :typeseed
            typeseed = kw.second
        elseif kw.first === :compat1
            if !(kw.second isa Bool)
                error_usage(__source__, "`compat1` argument must be a Bool, but got `$(kw.second)`.")
            end
            compat1 = kw.second
        else
            error_usage(__source__, "invalid keyword argument for @auto_hash_equals: `$(kw.first)`.")
        end
    end

    typ = get_struct_decl(__source__::LineNumberNode, typ)

    auto_hash_equals_impl(__source__, typ, fields, cache, hashfn, typearg, typeseed, compat1)
end

function auto_hash_equals_impl(__source__, struct_decl, fields, cache::Bool, hashfn, typearg::Bool, typeseed, compat1::Bool)
    is_expr(struct_decl, :struct) || error_usage(__source__)

    type_body = struct_decl.args[3].args

    (!cache || !struct_decl.args[1]) ||
        error_usage(__source__, "macro `@auto_hash_equals`` with `cached=true`` should only be applied to a non-mutable struct.")

    (type_name, full_type_name, where_list) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, member_decls) = get_fields(__source__, struct_decl; prevent_inner_constructors=cache)
    if isnothing(fields)
        fields = (member_names...,)
    else
        for f in fields
            f isa Symbol ||
                error_usage(__source__, "invalid field name: `$f`.")
            f in member_names ||
                error_usage(__source__, "field `$f` not found in struct `$type_name`.")
        end
    end

    base_hash_name = :($Base.hash)
    if isnothing(hashfn)
        hashfn = base_hash_name
    end

    # Add the cache field to the body of the struct
    if cache
        push!(type_body, :(_cached_hash::UInt))

        # Add the internal constructor
        hash_init = if isnothing(typeseed)
            if typearg
                :($type_seed($full_type_name))
            else
                :($hashfn($(QuoteNode(type_name))))
            end
        else
            if typearg
                :(UInt($typeseed($full_type_name)))
            else
                :(UInt($typeseed))
            end
        end
        compute_hash = foldl(
            (r, a) -> :($hashfn($a, $r)),
            fields;
            init = hash_init)
        ctor_body = :(new($(member_names...), $compute_hash))
        if isnothing(where_list)
            push!(type_body, :(function $full_type_name($(member_names...))
                $ctor_body
            end))
        else
            push!(type_body, :(function $full_type_name($(member_names...)) where {$(where_list...)}
                $ctor_body
            end))
        end
    end

    result = Expr(:block, __source__, esc(struct_decl), __source__)

    # add function for hash(x, h). hash(x)
    if cache
        push!(result.args, esc(:(function $hashfn(x::$type_name, h::UInt)
            $hashfn(x._cached_hash, h)
        end)))
        push!(result.args, esc(:(function $hashfn(x::$type_name)
            x._cached_hash
        end)))
    else
        hash_init =
            if isnothing(typeseed)
                if typearg
                    :($type_seed($full_type_name, h))
                else
                    :($hashfn($(QuoteNode(type_name)), h))
                end
            else
                if typearg
                    :(UInt($typeseed($full_type_name, h)))
                else
                    :(h + UInt($typeseed))
                end
            end
        compute_hash = foldl(
            (r, a) -> :($hashfn($getfield(x, $(QuoteNode(a))), $r)),
            fields;
            init = hash_init)
        if typearg
            if isnothing(where_list)
                push!(result.args, esc(:(function $hashfn(x::$full_type_name, h::UInt)
                    $compute_hash
                end)))
            else
                push!(result.args, esc(:(function $hashfn(x::$full_type_name, h::UInt) where {$(where_list...)}
                    $compute_hash
                end)))
            end
        else
            push!(result.args, esc(:(function $hashfn(x::$type_name, h::UInt)
                $compute_hash
            end)))
        end
    end

    if hashfn != base_hash_name
        # add function for Base.hash(x, h)
        push!(result.args, esc(:(function $base_hash_name(x::$type_name, h::UInt)
            $hashfn(x, h)
        end)))
        if cache
            push!(result.args, esc(:(function $base_hash_name(x::$type_name)
                $hashfn(x)
            end)))
        end
    end

    # add function Base.show
    if cache
        push!(result.args, esc(:(function $Base._show_default(io::IO, x::$type_name)
            $_show_default_auto_hash_equals_cached(io, x)
        end)))
    end

    # Add function to interoperate with Rematch2 (eventually Match.jl) if loaded
    # at the time the macro is expanded.
    if_has_package("Match", Base.UUID("7eb4fadd-790c-5f42-8a69-bfa0b872bfbf"), v"2") do pkg
        if :match_fieldnames in names(pkg; all=true)
            push!(result.args, esc(:(function $pkg.match_fieldnames(::Type{$type_name})
                $((fields...,))
            end)))
        end
    end

    if cache && !isnothing(where_list)
        # for generic types, we add an external constructor to perform ctor type inference:
        push!(result.args, esc(quote
            $type_name($(member_decls...)) where {$(where_list...)} = $full_type_name($(member_names...))
        end))
    end

    # Add the `==` and `isequal` functions
    for eq in (==, isequal)
        # In compat mode, only define ==
        eq == isequal && compat1 && continue

        if eq == isequal || compat1
            equality_impl = foldl(
                (r, f) -> :($r && $isequal($getfield(a, $(QuoteNode(f))), $getfield(b, $(QuoteNode(f))))),
                fields;
                init = cache ? :(a._cached_hash == b._cached_hash) : true)
            if struct_decl.args[1]
                # mutable structs can efficiently be compared by reference
                # Note this optimization is only valid for `isequal`, e.g.
                # a = [missing]
                # a == a # missing
                # isequal(a, a) # true
                equality_impl = :(a === b || $equality_impl)
            end
        else
            # Here we have a more complicated implementation in order to handle missings correctly.
            # If any field comparison is false, we return false (even if some return missing).
            # If no field comparisons are false, but one comparison missing, then we return missing.
            # Otherwise we return true.
            # (This matches the semantics of `==` for `Tuple`'s and `NamedTuple`'s.)
            equality_impl = Expr(:block, :(found_missing = false))
            if cache
                push!(equality_impl.args, :(a._cached_hash != b._cached_hash && return false))
            end
            for f in fields
                push!(equality_impl.args, :(cmp = $getfield(a, $(QuoteNode(f))) == $getfield(b, $(QuoteNode(f)))))
                push!(equality_impl.args, :(cmp === false && return false))
                push!(equality_impl.args, :($ismissing(cmp) && (found_missing = true)))
            end
            push!(equality_impl.args, :(return $ifelse(found_missing, missing, true)))
        end

        fn_name = Symbol(eq)
        if isnothing(where_list) || !typearg
            push!(result.args, esc(:(function ($Base).$fn_name(a::$type_name, b::$type_name)
                $equality_impl
            end)))
        else
            # If requested, require the type arguments be the same for two instances to be equal
            push!(result.args, esc(:(function ($Base).$fn_name(a::$full_type_name, b::$full_type_name) where {$(where_list...)}
                $equality_impl
            end)))
        end
    end

    # Evaluating a struct declaration normally returns the struct itself.
    # we preserve that behavior when the macro is used.
    # We also relay documentation to the struct type.
    push!(result.args, esc(:(Base.@__doc__ $type_name)))

    return result
end
