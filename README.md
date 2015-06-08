[![Build
Status](https://travis-ci.org/andrewcooke/AutoHashEquals.jl.png)](https://travis-ci.org/andrewcooke/AutoHashEquals.jl)
[![Coverage Status](https://coveralls.io/repos/andrewcooke/AutoHashEquals.jl/badge.svg)](https://coveralls.io/r/andrewcooke/AutoHashEquals.jl)
[![AutoHashEquals](http://pkg.julialang.org/badges/AutoHashEquals_release.svg)](http://pkg.julialang.org/?pkg=AutoHashEquals&ver=release)

# AutoHashEquals

A macro to add == and hash() to composite types (ie type and immutable
blocks).

For example:

```julia

@auto type Foo
    a::Int
    b
end
```

becomes

```julia
type Foo
    a::Int
    b
end
hash(a::Foo) = hash(a.b, hash(a.a, hash(:Foo)))
==(a::Foo, b::Foo) = isequal(a.b, b.b) && isequal(a.a, b.a) && true
```

Where

* we use `isequal()` because we want to match cached Inf values, etc.

* we include the type in the hash so that different types with the same
  contents don't collide

* the type and `true` make it simple to generate code for empty types

