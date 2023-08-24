# SPDX-License-Identifier: MIT

module AutoHashEquals

export @auto_hash_equals

include("type_key.jl")
include("impl.jl")

"""
    @auto_hash_equals [options] struct Foo ... end

Generate `Base.hash` and `Base.==` methods for `Foo`.

Options:

* `cache=true|false` whether or not to generate an extra cache field to store the precomputed hash value. Default: `false`.
* `hashfn=myhash` the hash function to use. Default: `Base.hash`.
* `fields=a,b,c` the fields to use for hashing and equality. Default: all fields.
* `typearg=true|false` whether or not to make type arguments significant. Default: `false`.
* `typeseed=e` Use `e` (or `e(type)` if `typearg=true`) as the seed for hashing type arguments.
"""
macro auto_hash_equals(args...)
    kwargs = Dict{Symbol,Any}()
    length(args) > 0 || error_usage(__source__)
    for option in args[1:end-1]
        if !isexpr(option, :(=), 2) || !(option.args[1] isa Symbol)
            error_usage(__source__, "expected keyword argument of the form `key=value`, but saw `$option`.")
        end
        name=option.args[1]
        value=option.args[2]
        if name == :fields
            # fields=a,b,c
            if value isa Symbol
                value = (value,)
            elseif isexpr(value, :tuple)
                value = Symbol[value.args...]
                value=(value...,)
            else
                error_usage(__source__, "expected tuple or symbol for `fields`, but got `$value`.")
            end
        end
        kwargs[name] = value
    end
    typ = args[end]
    auto_hash_equals_impl(__source__, typ; kwargs...)
end

end # module
