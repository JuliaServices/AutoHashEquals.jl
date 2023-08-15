using Pkg

const is_expr = Base.Meta.isexpr

function pkgversion(m::Module)
    pkgdir = dirname(string(first(methods(m.eval)).file))
    toml = Pkg.TOML.parsefile(joinpath(pkgdir, "..", "Project.toml"))
    VersionNumber(toml["version"])
end

function if_has_package(
    action::Function,
    name::String,
    uuid::Base.UUID,
    version::VersionNumber
)
    pkgid = Base.PkgId(uuid, name)
    if Base.root_module_exists(pkgid)
        pkg = Base.root_module(pkgid)
        if pkgversion(pkg) >= version
            return action(pkg)
        end
    end
end

function error_usage(__source__)
    usage=
    """
    Usage:
        @auto_hash_equals [options] struct Foo ... end

    Generate `Base.hash` and `Base.==` methods for `Foo`.

    Options:

    * `cache=true|false` whether or not to generate an extra cache field to store the precomputed hash value. Default: `false`.
    * `hashfn=myhash` the hash function to use. Default: `Base.hash`.
    * `fields=a,b,c` the fields to use for hashing and equality. Default: all fields.
    """
    error("$(__source__.file):$(__source__.line): $usage")
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
            error("$(__source__.file):$(__source__.line): macro @auto_hash_equals applied to type with invalid signature: `$type_name`")
        where_list = n.args[2:length(n.args)]
        type_params = map(unpack_name, where_list)
        full_type_name = Expr(:curly, type_name, type_params...)
        return (type_name, full_type_name, where_list)
    elseif n.head === :(<:)
        return unpack_type_name(__source__, n.args[1])
    else
        error("$(__source__.file):$(__source__.line): macro @auto_hash_equals applied to type with unexpected signature: `$n`")
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
                error("$(__source__.file):$(__source__.line): macro @auto_hash_equals should not be used on a struct that declares an inner constructor")
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
        error("$(__source__.file):$(__source__.line): invalid alternate hash function name: `$alt_hash_name`")
end

isexpr(e, head) = e isa Expr && e.head == head
isexpr(e, head, n) = isexpr(e, head) && length(e.args) == n

function auto_hash_equals_impl(__source__::LineNumberNode, typ; kwargs...)
    # These are the default values of the keyword arguments
    cache=false
    hashfn=nothing
    fields=nothing

    # Process the keyword arguments
    for kw in kwargs
        @assert kw isa Pair
        @assert kw.first isa Symbol
        if kw.first === :cache
            if !(kw.second isa Bool)
                error("$(__source__.file):$(__source__.line): `cache` argument must be a Bool, but got `$(kw.second)`")
            end
            cache = kw.second
        elseif kw.first === :hashfn
            if !(kw.second isa Union{Symbol, Expr, Function})
                error("$(__source__.file):$(__source__.line): `hashfn` argument must name a function, but got `$(kw.second)`")
            end
            hashfn = kw.second
            check_valid_alt_hash_name(__source__, hashfn)
        elseif kw.first === :fields
            if !(kw.second isa Tuple) || !all(f isa Symbol for f in kw.second)
                error("$(__source__.file):$(__source__.line): invalid `fields` argument: `$(kw.second)`.  Must be of the form `(x, y, z)`.")
            end
            fields = kw.second
        else
            error("$(__source__.file):$(__source__.line): invalid keyword argument for @auto_hash_equals: `$(kw.first)`")
        end
    end

    typ = get_struct_decl(__source__::LineNumberNode, typ)

    auto_hash_equals_impl(__source__, typ, fields, cache, hashfn)
end

function auto_hash_equals_impl(__source__, struct_decl, fields, cache::Bool, hashfn)
    is_expr(struct_decl, :struct) || error_usage(__source__)

    type_body = struct_decl.args[3].args

    (!cache || !struct_decl.args[1]) ||
        error("$(__source__.file):$(__source__.line): macro @auto_hash_equals with cached=true should only be applied to a non-mutable struct.")

    (type_name, full_type_name, where_list) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, member_decls) = get_fields(__source__, struct_decl; prevent_inner_constructors=cache)
    if isnothing(fields)
        fields = (member_names...,)
    else
        for f in fields
            f isa Symbol ||
                error("$(__source__.file):$(__source__.line): invalid field name: `$f`")
            f in member_names ||
                error("$(__source__.file):$(__source__.line): field `$f` not found in struct `$type_name`")
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
        compute_hash = foldl(
            (r, a) -> :($hashfn($a, $r)),
            fields;
            init = :($hashfn($full_type_name)))
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

    result = Expr(:block, __source__, esc(:(Base.@__doc__ $struct_decl)), __source__)

    # add function for hash(x, h). hash(x)
    if cache
        push!(result.args, esc(:(function $hashfn(x::$type_name, h::UInt)
                $hashfn(x._cached_hash, h)
            end)))
        push!(result.args, esc(:(function $hashfn(x::$type_name)
                x._cached_hash
            end)))
        if hashfn != base_hash_name
            # add function for Base.hash(x)
            push!(result.args, esc(:(function $base_hash_name(x::$type_name)
                    $hashfn(x)
                end)))
        end
    else
        compute_hash = foldl(
            (r, a) -> :($hashfn($getfield(x, $(QuoteNode(a))), $r)),
            fields;
            init = :($hashfn($(QuoteNode(type_name)), h)))
        push!(result.args, esc(:(function $hashfn(x::$type_name, h::UInt)
            $compute_hash
            end)))
    end

    if hashfn != base_hash_name
        # add function for Base.hash(x, h)
        push!(result.args, esc(:(function $base_hash_name(x::$type_name, h::UInt)
                $hashfn(x, h)
            end)))
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

    equalty_impl = foldl(
        (r, f) -> :($r && $isequal($getfield(a, $(QuoteNode(f))), $getfield(b, $(QuoteNode(f))))),
        fields;
        init = cache ? :(a._cached_hash == b._cached_hash) : true)
    if cache
        if isnothing(where_list)
            # add == for non-generic types
            push!(result.args, esc(quote
                function $Base.:(==)(a::$type_name, b::$type_name)
                    $equalty_impl
                end
            end))
        else
            # We require the type be the same (including type arguments) for two instances to be equal
            push!(result.args, esc(quote
                function $Base.:(==)(a::$full_type_name, b::$full_type_name) where {$(where_list...)}
                    $equalty_impl
                end
            end))
            # for generic types, we add an external constructor to perform ctor type inference:
            push!(result.args, esc(quote
                $type_name($(member_decls...)) where {$(where_list...)} = $full_type_name($(member_names...))
            end))
        end
    else
        if struct_decl.args[1]
            # mutable structs can efficiently be compared by reference
            equalty_impl = :(a === b || $equalty_impl)
        end
        # for compatibility with earlier versions of
        # [AutoHashEquals.jl](https://github.com/andrewcooke/AutoHashEquals.jl)
        # we do not require that the types (specifically, the type arguments) are the
        # same for two objects to be considered `==` when not cacheing the hash code.
        push!(result.args, esc(:(function $Base.:(==)(a::$type_name, b::$type_name)
            $equalty_impl
            end)))
    end

    # Evaluating a struct declaration normally returns the struct itself.
    # Lets preserve that.
    push!(result.args, esc(type_name))

    return result
end
