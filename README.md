[![Build Status](https://travis-ci.org/andrewcooke/AutoHashEquals.jl.png)](https://travis-ci.org/andrewcooke/AutoHashEquals.jl)
[![Coverage Status](https://coveralls.io/repos/andrewcooke/AutoHashEquals.jl/badge.svg)](https://coveralls.io/r/andrewcooke/AutoHashEquals.jl)

[![AutoHashEquals](http://pkg.julialang.org/badges/AutoHashEquals_0.3.svg)](http://pkg.julialang.org/?pkg=AutoHashEquals&ver=0.3)
[![AutoHashEquals](http://pkg.julialang.org/badges/AutoHashEquals_0.4.svg)](http://pkg.julialang.org/?pkg=AutoHashEquals&ver=0.4)
[![AutoHashEquals](http://pkg.julialang.org/badges/AutoHashEquals_0.5.svg)](http://pkg.julialang.org/?pkg=AutoHashEquals&ver=0.5)

# AutoHashEquals

A macro to add == and hash() to composite types (ie type and immutable
blocks).

For example:

```julia
@auto_hash_equals type Foo
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
Base.hash(a::Foo, h::UInt) = hash(a.b, hash(a.a, hash(:Foo, h)))
Base.(:(==))(a::Foo, b::Foo) = isequal(a.b, b.b) && isequal(a.a, b.a) && true
```

Where

* we use `isequal()` because we want to match `Inf` values, etc.

* we include the type in the hash so that different types with the same
  contents don't collide

* the type and `true` make it simple to generate code for empty records

* the `Base` module is explicitly used so that you don't need to
  import it

## Background

Julia has two composite types: *value* types, defined with `immutable`, and
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

## Warnings

If you use this macro for a mutable type, then the hash depends on the
contents of that type, so changing the contents changes the hash.  Such types
should not be stored in a hash table (Dict) and then mutated, because the
objects will be "lost" (as the hash table *assumes* that hash is constant).

More generally, **this macro is only useful for mutable types when they are
used as *immutable* records**.

## Credits

Thanks to Michael Hatherly on julia-users and Yichao Yu.
