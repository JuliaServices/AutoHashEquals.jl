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
0xb7650cb555d6aafa

julia> hash(Box2{Any}(1))
0xefe691a94f296c61
```
