[![Build
Status](https://travis-ci.org/andrewcooke/AutoHashEquals.jl.png)](https://travis-ci.org/andrewcooke/AutoHashEquals.jl)
[![Coverage Status](https://coveralls.io/repos/andrewcooke/AutoHashEquals.jl/badge.svg)](https://coveralls.io/r/andrewcooke/AutoHashEquals.jl)
[![AutoHashEquals](http://pkg.julialang.org/badges/AutoHashEquals_release.svg)](http://pkg.julialang.org/?pkg=AutoHashEquals&ver=release)

# AutoHashEquals

A macro to add == and hash() to composite types (ie type and immutable
blocks).

For example:

```julia
import Base.hash

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

* we use `isequal()` because we want to match `Inf` values, etc.

* we include the type in the hash so that different types with the same
  contents don't collide

* the type and `true` make it simple to generate code for empty records

## Background

Julia has two composite types: *value* types, defined with `immutable` and
*record* types, defined with `type`.

Value types are intended for compact, immutable objects.  They are stored on
the stack, passed by value, and the default hash and equality are based on the
literal bits in memory.

Record types are allocated on the heap, are passed by reference, and the
default hash and equality are based on the pointer value (the data address).

When you embed a record type in a value type, then the pointer to the record
type becomes part of the value type, and so is included in equality and hash.

Given the above, it is often necessary to define hash and equality for
composite types.  Particularly when record types are used (directly, or in a
value type), and when records with the same contents are semantically equal.

A common way to do this is to define the hash as a combination of the hashes
of all the fields.  Similarly, equality is often defined as equality of all
fields.

This macro automates this common approach.
