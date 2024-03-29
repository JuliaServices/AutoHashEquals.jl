[![Build Status](https://github.com/JuliaServices/AutoHashEquals.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaServices/AutoHashEquals.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaServices/AutoHashEquals.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaServices/AutoHashEquals.jl)

# AutoHashEquals.jl - Automatically define hash and equals for Julia.

A macro to add `isequal`, `==`, and `hash()` to struct types: `@auto_hash_equals`.

# `@auto_hash_equals`

The macro `@auto_hash_equals` produces an implementation of `Base.hash(x)` that computes the hash code when invoked.

You use it like so:

```julia
@auto_hash_equals struct Box{T}
    x::T
end
```

which is translated to

```julia
struct Box{T}
    x::T
end
Base.hash(x::Box, h::UInt) = hash(x.x, hash(:Box, h))
Base.(:(==))(a::Box, b::Box) = a.x == b.x
Base.isequal(a::Box, b::Box) = isequal(a.x, b.x)
```

We do not take the type arguments of a generic type into account for `isequal`, `hash`, or `==` unless `typearg=true` is specified (see below).  So by default, a `Box{Int}(1)` will test equal to a `Box{Any}(1)`.

## User-specified hash function

You can specify the hash function to be implemented, by naming it before the struct definition with a keyword argument `hashfn`:

```julia
@auto_hash_equals hashfn=SomePackage.myhash struct Foo
    x
    y
end
```

In this case the macro implements both `SomePackage.myhash` and `Base.hash` for `Foo`.`

## Caching the hash value

You can have the hash value precomputed and stored in a hidden field, by adding the keyword argument `cache=true`. This useful for non-mutable struct types that define recursive or deep data structures (and therefore are likely to be stored on the heap).  It computes the hash code during construction and caches it in a field of the struct.  If you are working with data structures of any significant depth, computing the hash once can speed things up at the expense of one additional field per struct.

```julia
@auto_hash_equals cache=true struct Box{T}
    x::T
end
```

this translates to

```julia
struct Box{T}
    x::T
    _cached_hash::UInt
    function Box{T}(x) where T
        new(x, Base.hash(x, Base.hash(:Box)))
    end
end
function Base.hash(x::Box, h::UInt)
    Base.hash(x._cached_hash, h)
end
function Base.hash(x::Box)
    x._cached_hash
end
function Base._show_default(io::IO, x::Box)
    AutoHashEqualsCached._show_default_auto_hash_equals_cached(io, x)
end
# Note: the definition of `==` is more complicated when there are more fields,
# in order to handle `missing` correctly. See below for a more complicated example.
function Base.:(==)(a::Box, b::Box)
    a._cached_hash == b._cached_hash && Base.:(==)(a.x, b.x)
end
function Base.isequal(a::Box, b::Box)
    a._cached_hash == b._cached_hash && Base.isequal(a.x, b.x)
end
function Box(x::T) where T
    Box{T}(x)
end
```

The definition of `_show_default(io,x)` prevents display of the `_cached_hash` field while preserving the behavior of `Base.show(...)` that handles self-recursive data structures without a stack overflow.

We provide an external constructor for generic types so that you get the same type inference behavior you would get in the absence of this macro.  Specifically, you can write `Box(1)` to get an object of type `Box{Int}`.

## Specifying significant fields

You can specify which fields should be significant for the purposes of computing the hash function and checking equality:

```julia
@auto_hash_equals fields=(a,b) struct Foo
    a
    b
    c
end
```

this translates to

```julia
struct Foo
    a
    b
    c
end
function Base.hash(x::Foo, h::UInt)
    Base.hash(x.b, Base.hash(x.a, Base.hash(:Foo, h)))
end
function Base.isequal(a::Foo, b::Foo)
    Base.isequal(a.a, b.a) && Base.isequal(a.b, b.b)
end
# Returns `false` if any two fields compare as false; otherwise, `missing` if at least
# one comparison is missing. Otherwise `true`.
# This matches the semantics of `==` for Tuple's and NamedTuple's.
function Base.:(==)(a::Foo, b::Foo)
    found_missing = false
    cmp = a.a == b.a
    cmp === false && return false
    if ismissing(cmp)
        found_missing = true
    end
    cmp = a.b == b.b
    cmp === false && return false
    if ismissing(cmp)
        found_missing = true
    end
    found_missing && return missing
    return true
end
```

## Specifying whether or not type arguments should be significant

You can specify that type arguments should be significant for the purposes of computing the hash function and checking equality by adding the keyword parameter `typearg=true`.  By default they are not significant.  You can specify the default (they are not significant) with `typearg=false`:

```julia
julia> @auto_hash_equals struct Box1{T}
           x::T
       end
Box1

julia> Box1{Int}(1) == Box1{Any}(1)
true

julia> hash(Box1{Int}(1))
0x05014b35fc91d289

julia> hash(Box1{Any}(1))
0x05014b35fc91d289

julia> @auto_hash_equals typearg=true struct Box2{T}
           x::T
       end
Box2

julia> Box2{Int}(1) == Box2{Any}(1)
false

julia> hash(Box2{Int}(1))
0x467811eefea1d458

julia> hash(Box2{Any}(1))
0x3042fd2f8fe839d7
```

## Specifying the "type seed"

When we compute the hash function, we start with a "seed" specific to the type being hashed.
By default, the seed is computed as `Base.hash(:TypeName)` if `typearg=false` (which is the default).
If `typearg=true` was specified, then the seed is computed as `type_seed(Type)`,
where `Type` is the type of the instance, including any type arguments.  `type_seed` is a
stable hash function defined (but not exported) in this package.

You can select the seed to be used by specifying `typeseed=e`.

The seed provided (`e`) is used in one of two ways, depending on the setting for `typearg`.
If `typearg=false` (the default), then the value `e` will be used as the type seed.
If `typearg=true`, then `e(t)` is used as the type seed, where `t` is the type of the object being hashed.

Note that the value of `typeseed` is expected to be a `UInt` value when `typearg=false` (or `typearg` is not specified),
but a function that takes a type as its argument when `typearg=true`.

## Compatibility mode

In versions `v"1.0"` and earlier of `AutoHashEquals`, we produced a specialization of `Base.==`, implemented using `Base.isequal`.
This was not correct.
See https://docs.julialang.org/en/v1/base/base/#Base.isequal and https://docs.julialang.org/en/v1/base/math/#Base.:==.
More correct would be to define `==` by using `==` on the members, and to define `isequal` by using `isequal` on the members.
In version `v"2.0"` we provide a correct implementation, thanks to @ericphanson.

To get the same behavior as `v"1.0"` of this package, in which `==` is implemented based on `isequal`,
you can specify `compat1=true`.

```julia
@auto_hash_equals struct Box890{T}
    x::T
end
@assert ismissing(Box890(missing) == Box890(missing))
@assert isequal(Box890(missing), Box890(missing))
@assert ismissing(Box890(missing) == Box890(1))
@assert !isequal(Box890(missing), Box890(1))

@auto_hash_equals compat1=true struct Box891{T}
    x::T
end
@assert Box891(missing) == Box891(missing)
@assert isequal(Box891(missing), Box891(missing))
@assert Box891(missing) != Box891(1)
@assert !isequal(Box891(missing), Box891(1))
```

If you need compatibility mode always and don't want to have to specify the mode on each invocation,
you can instead import the compatibility version of the macro, which defaults to `compat1=true':

```julia
using AutoHashEquals.Compat
```
