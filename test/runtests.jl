# SPDX-License-Identifier: MIT

module runtests

using AutoHashEquals: @auto_hash_equals
using Markdown: plain
using Match: Match, @match, MatchFailure
using Random
using Serialization
using Test

# Import private member for test purposes
using AutoHashEquals: type_seed

function serialize_and_deserialize(x)
    buf = IOBuffer()
    serialize(buf, x)
    seekstart(buf)
    deserialize(buf)
end

macro noop(x)
    esc(x)
end

macro _const(x)
    # const fields were introduced in Julia 1.8
    if VERSION >= v"1.8"
        esc(Expr(:const , x))
    else
        esc(x)
    end
end

"""
    @auto_hash_equals_cached struct Foo ... end

Shorthand for @auto_hash_equals cache=true struct Foo ... end
"""
macro auto_hash_equals_cached(typ)
    esc(Expr(:macrocall, var"@auto_hash_equals", __source__, :(cache = true), typ))
end

# some custom hash function
function myhash end
myhash(o::T, h::UInt) where {T} = error("myhash not implemented for $T")
myhash(o::UInt, h::UInt) = xor(o, h)
myhash(o::Symbol, h::UInt) = Base.hash(o, h)
myhash(o::Type, h::UInt) = myhash(o.name.name, h)
myhash(o) = myhash(o, UInt(0x0))

# Some types for testing interoperation with `Match.jl`
struct R157; x; y; end
@auto_hash_equals_cached struct R158; x; y::Int; end
@auto_hash_equals_cached struct R159{T}; x; y::T; end

@auto_hash_equals fields=(a, b) struct R477
    a
    b
    ignore_me
end
@auto_hash_equals cache=true fields=(a, b) struct R478
    a
    b
    ignore_me
end

struct G{T, U}
    x::T
    y::U
end

abstract type Q end
abstract type B{T} end
@enum E e1 e2 e3

@testset "AutoHashEquals.jl" begin

    @testset "tests for @auto_hash_equals_cached" begin

        @testset "macro preserves comments 1" begin
            """a comment"""
            @auto_hash_equals_cached struct T23
                x
            end
            @test plain(@doc T23) == "a comment\n"
        end

        @testset "macro preserves comments 2" begin
            """a comment"""
            @auto_hash_equals_cached @noop struct T26
                x
            end
            @test plain(@doc T26) == "a comment\n"
        end

        @testset "macro preserves comments 3" begin
            """a comment"""
            @noop @auto_hash_equals_cached struct T30
                @noop x
            end
            @test plain(@doc T30) == "a comment\n"
        end

        @testset "the macro sees through other macros and `begin`" begin
            @auto_hash_equals_cached @noop struct T32
                @noop begin
                    @noop x
                end
            end
            @test T32(1) == T32(1)
            @test hash(T32(1)) == hash(T32(1))
            @test hash(T32(1)) != hash(T32(2))
        end

        @testset "the macro sees through `const`" begin
            if VERSION >= v"1.8"
                T33 = eval(:(@auto_hash_equals mutable struct T33
                    @_const x
                end))
                @test T33(1) == T33(1)
                @test hash(T33(1)) == hash(T33(1))
                @test hash(T33(1)) != hash(T33(2))
            end
        end

        @testset "misuse of the macro" begin
            @test_throws Exception @eval @auto_hash_equals a struct T34 end
        end

        @testset "invalid type name 1" begin
            @test_throws Exception @eval @auto_hash_equals_cached struct 1 end
        end

        @testset "invalid type name 2" begin
            @test_throws Exception @eval @auto_hash_equals_cached struct a.b end
        end

        @testset "empty struct" begin
            @auto_hash_equals_cached struct T35 end
            @test T35() isa T35
            @test hash(T35()) == hash(:T35)
            @test hash(T35(), UInt(0)) == hash(hash(:T35), UInt(0))
            @test hash(T35(), UInt(1)) == hash(hash(:T35), UInt(1))
            @test T35() == T35()
            @test T35() == serialize_and_deserialize(T35())
            @test hash(T35()) == hash(serialize_and_deserialize(T35()))
            @test "$(T35())" == "$(T35)()"
        end

        @testset "struct with members" begin
            @auto_hash_equals_cached struct T48
                x; y
            end
            @test T48(1, :x) isa T48
            @test hash(T48(1, :x)) == hash(:x,hash(1,hash(:T48)))
            @test T48(1, :x) == T48(1, :x)
            @test T48(1, :x) != T48(2, :x)
            @test hash(T48(1, :x)) != hash(T48(2, :x))
            @test T48(1, :x) != T48(1, :y)
            @test hash(T48(1, :x)) != hash(T48(1, :y))
            @test T48(1, :x) == serialize_and_deserialize(T48(1, :x))
            @test hash(T48(1, :x)) == hash(serialize_and_deserialize(T48(1, :x)))
            @test "$(T48(1, :x))" == "$(T48)(1, :x)"
        end

        @testset "generic struct with members" begin
            @auto_hash_equals cache=true typearg=true struct T63{G}
                x
                y::G
            end
            @test T63{Symbol}(1, :x) isa T63
            @test hash(T63{Symbol}(1, :x)) == hash(:x,hash(1,type_seed(T63{Symbol})))
            @test hash(T63{Symbol}(1, :x)) != hash(T63{Any}(1, :x))
            @test T63{Symbol}(1, :x) != T63{Any}(1, :x) # note: type args are significant
            @test T63{Symbol}(1, :x) == T63{Symbol}(1, :x)
            @test T63{Symbol}(1, :x) != T63{Symbol}(2, :x)
            @test hash(T63{Symbol}(1, :x)) != hash(T63{Symbol}(2, :x))
            @test T63{Symbol}(1, :x) != T63{Symbol}(1, :y)
            @test hash(T63{Symbol}(1, :x)) != hash(T63{Symbol}(1, :y))
            @test T63{Symbol}(1, :x) == serialize_and_deserialize(T63{Symbol}(1, :x))
            @test hash(T63{Symbol}(1, :x)) == hash(serialize_and_deserialize(T63{Symbol}(1, :x)))
        end

        @testset "inheritance from an abstract base" begin
            abstract type Base81 end
            @auto_hash_equals_cached struct T81a<:Base81 x end
            @auto_hash_equals_cached struct T81b<:Base81 x end
            @test T81a(1) isa T81a
            @test T81a(1) isa Base81
            @test T81b(1) isa T81b
            @test T81b(1) isa Base81
            @test T81a(1) != T81b(1)
            @test T81a(1) == T81a(1)
            @test serialize_and_deserialize(T81a(1)) isa T81a
            @test T81a(1) == serialize_and_deserialize(T81a(1))
            @test hash(T81a(1)) == hash(serialize_and_deserialize(T81a(1)))
        end

        @testset "generic bounds" begin
            abstract type Base107{T<:Union{String, Int}} end
            @auto_hash_equals cache=true typearg=true struct T107a{T}<:Base107{T} x::T end
            @auto_hash_equals cache=true typearg=true struct T107b{T}<:Base107{T} x::T end
            @test T107a(1) isa T107a
            @test T107a(1) == T107a(1)
            @test T107a(1) == serialize_and_deserialize(T107a(1))
            @test T107a(1) != T107a(2)
            @test hash(T107a(1)) == hash(1, type_seed(T107a{Int}))
            @test hash(T107a("x")) == hash("x", type_seed(T107a{String}))
            @test hash(T107a(1)) != hash(T107b(1))
            @test hash(T107a(1)) != hash(T107a(2))
        end

        @testset "macro applied to type before @auto_hash_equals_cached" begin
            @noop @auto_hash_equals_cached struct T116
                x::Int
                y
            end
            @test T116(1, :x) isa T116
            @test hash(T116(1, :x)) == hash(:x,hash(1,hash(:T116)))
            @test T116(1, :x) == T116(1, :x)
            @test T116(1, :x) != T116(2, :x)
            @test hash(T116(1, :x)) != hash(T116(2, :x))
            @test T116(1, :x) != T116(1, :y)
            @test hash(T116(1, :x)) != hash(T116(1, :y))
            @test T116(1, :x) == serialize_and_deserialize(T116(1, :x))
            @test hash(T116(1, :x)) == hash(serialize_and_deserialize(T116(1, :x)))
        end

        @testset "macro applied to type after @auto_hash_equals_cached" begin
            @auto_hash_equals_cached @noop struct T132
                x::Int
                y
            end
            @test T132(1, :x) isa T132
            @test hash(T132(1, :x)) == hash(:x,hash(1,hash(:T132)))
            @test T132(1, :x) == T132(1, :x)
            @test T132(1, :x) != T132(2, :x)
            @test hash(T132(1, :x)) != hash(T132(2, :x))
            @test T132(1, :x) != T132(1, :y)
            @test hash(T132(1, :x)) != hash(T132(1, :y))
            @test T132(1, :x) == serialize_and_deserialize(T132(1, :x))
            @test hash(T132(1, :x)) == hash(serialize_and_deserialize(T132(1, :x)))
        end

        @testset "macro applied to members" begin
            @auto_hash_equals_cached @noop struct T135
                @noop x::Int
                @noop y
            end
            @test T135(1, :x) isa T135
            @test hash(T135(1, :x)) == hash(:x,hash(1,hash(:T135)))
            @test T135(1, :x) == T135(1, :x)
            @test T135(1, :x) != T135(2, :x)
            @test hash(T135(1, :x)) != hash(T135(2, :x))
            @test T135(1, :x) != T135(1, :y)
            @test hash(T135(1, :x)) != hash(T135(1, :y))
            @test T135(1, :x) == serialize_and_deserialize(T135(1, :x))
            @test hash(T135(1, :x)) == hash(serialize_and_deserialize(T135(1, :x)))
        end

        @testset "contained NaN values compare isequal (but not ==)" begin
            @auto_hash_equals_cached struct T140
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test isequal(T140(nan), T140(nan))
            @test T140(nan) != T140(nan)

        end

        @testset "circular data structures behavior" begin
            @auto_hash_equals_cached struct T145
                a::Array{Any,1}
            end
            t::T145 = T145(Any[1])
            t.a[1] = t
            # hash does not stack overflow thanks to the cache
            @test hash(t) != 0
            # `==` overflows
            @test_throws StackOverflowError t == t
            # isequal does not
            @test isequal(t, t)
            @test !isequal(t, T145(Any[]))
            # Check printing
            @test "$t" == "$(T145)(Any[$(T145)(#= circular reference @-2 =#)])"
        end

        # @test_throws requires a type before v1.8.
        internal_constructor_error =
            if VERSION >= v"1.7"
                ErrorException
            else
                LoadError
            end

        @testset "give an error if the struct contains internal constructors 1" begin
            @test_throws internal_constructor_error begin
                @macroexpand @auto_hash_equals_cached struct T150
                    T150() = new()
                end
            end
        end

        @testset "give an error if the struct contains internal constructors 2" begin
            @test_throws internal_constructor_error begin
                @macroexpand @auto_hash_equals_cached struct T152
                    T152() where {T} = new()
                end
            end
        end

        @testset "give an error if the struct contains internal constructors 3" begin
            @test_throws internal_constructor_error begin
                @macroexpand @auto_hash_equals_cached struct T154
                    function T154()
                        new()
                    end
                end
            end
        end

        @testset "test interoperation with Match" begin

            @testset "test simple Match usage" begin
                @test (Match.@match R157(z,2) = R157(1,2)) == R157(1,2) && z == 1
                @test_throws Match.MatchFailure Match.@match R157(x, 3) = R157(1,2)
                @test (Match.@match R157(1,2) begin
                    R157(x=x1,y=y1) => (x1,y1)
                end) == (1,2)
            end

            @testset "make sure Match works for types with cached hash code" begin
                @test (Match.@match R158(x,2) = R158(1,2)) == R158(1,2) && x == 1
                @test_throws Match.MatchFailure Match.@match R158(x, 3) = R158(1,2)
                @test (Match.@match R158(1,2) begin
                    R158(x=x1,y=y1) => (x1,y1)
                end) == (1,2)
            end

            @testset "make sure Match works for generic types with cached hash code" begin
                @test (Match.@match R159(x,2) = R159(1,2)) == R159(1,2) && x == 1
                @test_throws Match.MatchFailure Match.@match R159(x, 3) = R159(1,2)
                @test (Match.@match R159(1,2) begin
                    R159(x=x1,y=y1) => (x1,y1)
                end) == (1,2)
            end

        end

        @testset "give an error if the struct contains internal constructors 4" begin
            @test_throws internal_constructor_error begin
                @macroexpand @auto_hash_equals_cached struct T156
                    function T156() where {T}
                        new()
                    end
                end
            end
        end

        @testset "check compatibility with default constructor" begin
            @auto_hash_equals_cached struct S268
                x::Int
            end
            @test S268(2.0).x === 2
            @auto_hash_equals_cached struct S269{T <: Any}
                x::T
            end
            @test S269{Int}(2.0).x === 2
            @test S269(2.0).x === 2.0
        end
    end

    @testset "tests for @auto_hash_equals" begin

        @testset "macro preserves comments 1" begin
            """a comment"""
            @auto_hash_equals struct T160
                x
            end
            @test plain(@doc T160) == "a comment\n"
        end

        @testset "macro preserves comments 2" begin
            """a comment"""
            @auto_hash_equals @noop struct T165
                x
            end
            @test plain(@doc T165) == "a comment\n"
        end

        @testset "macro preserves comments 3" begin
            """a comment"""
            @noop @auto_hash_equals struct T170
                @noop x
            end
            @test plain(@doc T170) == "a comment\n"
        end

        @testset "empty struct" begin
            @auto_hash_equals struct T176 end
            @test T176() isa T176
            @test hash(T176()) == hash(:T176, UInt(0))
            @test hash(T176(), UInt(1)) == hash(:T176, UInt(1))
            @test hash(T176(), UInt(1)) != hash(:T176, UInt(0))
            @test T176() == T176()
            @test T176() == serialize_and_deserialize(T176())
            @test hash(T176()) == hash(serialize_and_deserialize(T176()))
        end

        @testset "struct with members" begin
            @auto_hash_equals struct T186
                x; y
            end
            @test T186(1, :x) isa T186
            @test hash(T186(1, :x)) == hash(:x,hash(1,hash(:T186, UInt(0))))
            @test T186(1, :x) == T186(1, :x)
            @test T186(1, :x) != T186(2, :x)
            @test hash(T186(1, :x)) != hash(T186(2, :x))
            @test T186(1, :x) != T186(1, :y)
            @test hash(T186(1, :x)) != hash(T186(1, :y))
            @test T186(1, :x) == serialize_and_deserialize(T186(1, :x))
            @test hash(T186(1, :x)) == hash(serialize_and_deserialize(T186(1, :x)))
        end

        @testset "generic struct with members" begin
            @auto_hash_equals typearg=false struct T201{G}
                x
                y::G
            end
            @test T201{Symbol}(1, :x) isa T201
            @test hash(T201{Symbol}(1, :x)) == hash(:x,hash(1,hash(:T201, UInt(0))))
            @test hash(T201{Symbol}(1, :x)) == hash(T201{Any}(1, :x))
            @test T201{Symbol}(1, :x) == T201{Any}(1, :x) # note: type args are not significant
            @test T201{Symbol}(1, :x) == T201{Symbol}(1, :x)
            @test T201{Symbol}(1, :x) != T201{Symbol}(2, :x)
            @test hash(T201{Symbol}(1, :x)) != hash(T201{Symbol}(2, :x))
            @test T201{Symbol}(1, :x) != T201{Symbol}(1, :y)
            @test hash(T201{Symbol}(1, :x)) != hash(T201{Symbol}(1, :y))
            @test T201{Symbol}(1, :x) == serialize_and_deserialize(T201{Symbol}(1, :x))
            @test hash(T201{Symbol}(1, :x)) == hash(serialize_and_deserialize(T201{Symbol}(1, :x)))
        end

        @testset "inheritance from an abstract base" begin
            abstract type Base219 end
            @auto_hash_equals struct T219a<:Base219 x end
            @auto_hash_equals struct T219b<:Base219 x end
            @test T219a(1) isa T219a
            @test T219a(1) isa Base219
            @test T219b(1) isa T219b
            @test T219b(1) isa Base219
            @test T219a(1) != T219b(1)
            @test T219a(1) == T219a(1)
            @test serialize_and_deserialize(T219a(1)) isa T219a
            @test T219a(1) == serialize_and_deserialize(T219a(1))
            @test hash(T219a(1)) == hash(serialize_and_deserialize(T219a(1)))
            @test hash(T219a(1)) == hash(1, hash(:T219a, UInt(0)))
        end

        @testset "generic bounds" begin
            abstract type Base225{T<:Union{String, Int}} end
            @auto_hash_equals typearg=false struct T225a{T}<:Base225{T} x::T end
            @auto_hash_equals typearg=false struct T225b{T}<:Base225{T} x::T end
            @test T225a(1) == T225a(1)
            @test T225a(1) == serialize_and_deserialize(T225a(1))
            @test T225a(1) != T225a(2)
            @test hash(T225a(1)) == hash(1, hash(:T225a, UInt(0)))
            @test hash(T225a("x")) == hash("x", hash(:T225a, UInt(0)))
            @test hash(T225a(1)) != hash(T225b(1))
            @test hash(T225a(1)) != hash(T225a(2))
        end

        @testset "macro applied to type before @auto_hash_equals" begin
            @noop @auto_hash_equals struct T238
                x::Int
                y
            end
            @test T238(1, :x) isa T238
            @test hash(T238(1, :x)) == hash(:x,hash(1,hash(:T238, UInt(0))))
            @test T238(1, :x) == T238(1, :x)
            @test T238(1, :x) != T238(2, :x)
            @test hash(T238(1, :x)) != hash(T238(2, :x))
            @test T238(1, :x) != T238(1, :y)
            @test hash(T238(1, :x)) != hash(T238(1, :y))
            @test T238(1, :x) == serialize_and_deserialize(T238(1, :x))
            @test hash(T238(1, :x)) == hash(serialize_and_deserialize(T238(1, :x)))
        end

        @testset "macro applied to type after @auto_hash_equals" begin
            @auto_hash_equals @noop struct T254
                x::Int
                y
            end
            @test T254(1, :x) isa T254
            @test hash(T254(1, :x)) == hash(:x,hash(1,hash(:T254, UInt(0))))
            @test T254(1, :x) == T254(1, :x)
            @test T254(1, :x) != T254(2, :x)
            @test hash(T254(1, :x)) != hash(T254(2, :x))
            @test T254(1, :x) != T254(1, :y)
            @test hash(T254(1, :x)) != hash(T254(1, :y))
            @test T254(1, :x) == serialize_and_deserialize(T254(1, :x))
            @test hash(T254(1, :x)) == hash(serialize_and_deserialize(T254(1, :x)))
        end

        @testset "macro applied to members" begin
            @auto_hash_equals @noop struct T313
                @noop x::Int
                @noop y
            end
            @test T313(1, :x) isa T313
            @test hash(T313(1, :x)) == hash(:x,hash(1,hash(:T313, UInt(0))))
            @test T313(1, :x) == T313(1, :x)
            @test T313(1, :x) != T313(2, :x)
            @test hash(T313(1, :x)) != hash(T313(2, :x))
            @test T313(1, :x) != T313(1, :y)
            @test hash(T313(1, :x)) != hash(T313(1, :y))
            @test T313(1, :x) == serialize_and_deserialize(T313(1, :x))
            @test hash(T313(1, :x)) == hash(serialize_and_deserialize(T313(1, :x)))
        end

        @testset "contained NaN values compare isequal (but not ==)" begin
            @auto_hash_equals struct T330
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test isequal(T330(nan), T330(nan))
            @test T330(nan) != T330(nan)
        end

        @testset "give no error if the struct contains internal constructors" begin
            @auto_hash_equals struct T350
                T350() = new()
            end
        end

        @testset "check that we can define custom hash function" begin
            @auto_hash_equals hashfn=runtests.myhash struct S470
                x::UInt
            end
            q, r = rand(RandomDevice(), UInt, 2)
            @test myhash(S470(q)) == hash(S470(q))
            @test myhash(S470(q), r) == hash(S470(q), r)
            r !== 0 && @test myhash(S470(q), r) != hash(S470(q))
        end

        @testset "fields are obeyed for the hash function and for pattern-matching 1" begin
            a = R477(1, 2, 3)
            b = R477(1, 2, 4)
            c = R477(1, 3, 3)
            d = R477(2, 2, 3)
            @test a == b
            @test a != c
            @test a != d
            @test c != d
            @test hash(a) == hash(b)
            @test hash(a) != hash(c)
            @test hash(a) != hash(d)
            @test hash(c) != hash(d)
            @test @match a begin
                R477(1, 2) => true
                _ => false
            end
        end

        @testset "fields are obeyed for the hash function and for pattern-matching 2" begin
            a = R478(1, 2, 3)
            b = R478(1, 2, 4)
            c = R478(1, 3, 3)
            d = R478(2, 2, 3)
            @test a == b
            @test a != c
            @test a != d
            @test c != d
            @test hash(a) == hash(b)
            @test hash(a) != hash(c)
            @test hash(a) != hash(d)
            @test hash(c) != hash(d)
            @test @match a begin
                R478(1, 2) => true
                _ => false
            end
        end

        @testset "you may not name nonexistent fields" begin
            @test_throws Exception @eval @auto_hash_equals fields=(x, z) struct S477
                x
                y
            end
        end

        @testset "bad field name" begin
            @test_throws Exception @eval @auto_hash_equals fields=(x, 1) struct S478
                x
                y
            end
        end

        @testset "You may name a single field" begin
            @auto_hash_equals fields=(x) struct S479
                x
                y
            end
            @test S479(1, 2) == S479(1, 3)
            @test hash(S479(1, 2)) == hash(S479(1, 3))
        end

        @testset "Test when type included in hash 1" begin
            @auto_hash_equals typearg=true struct S590{T}
                x::T
            end
            @test hash(S590{Int}(1)) == hash(1, type_seed(S590{Int}, UInt(0)))
            @test hash(S590{Int}(1), UInt(0x2)) == hash(1, type_seed(S590{Int}, UInt(0x2)))
            @test S590{Int}(1) != S590{Any}(1)
            @test hash(S590{Int}(1)) != hash(S590{Any}(1))
        end

        @testset "Test when type included in hash 2" begin
            @auto_hash_equals typearg=true cache=true struct S597{T}
                x::T
            end
            @test hash(S597{Int}(1)) == hash(1, type_seed(S597{Int}, UInt(0)))
            @test hash(S597{Int}(1), UInt(0x2)) == hash(hash(1, type_seed(S597{Int}, UInt(0))), UInt(0x2))
        end

        @testset "Test when type NOT included in hash 1" begin
            @auto_hash_equals typearg=false struct S607{T}
                x::T
            end
            @test hash(S607{Int}(1)) == hash(1, hash(:S607, UInt(0)))
            @test hash(S607{Int}(1), UInt(0x2)) == hash(1, hash(:S607, UInt(0x2)))
        end

        @testset "Test when type NOT included in hash 2" begin
            @auto_hash_equals typearg=false cache=true struct S615{T}
                x::T
            end
            @test hash(S615{Int}(1)) == hash(1, hash(:S615))
            @test hash(S615{Int}(1), UInt(0x2)) == hash(hash(1, hash(:S615)), UInt(0x2))
        end

        @testset "typearg keyword parameter must be a bool" begin
            @test_throws Exception @eval @auto_hash_equals typearg=1 struct S625{T}
                x::T
            end
        end

        @testset "check that type arguments are ignored by default" begin
            @auto_hash_equals struct Box629{T}
                x::T
            end
            @test Box629{Int}(1) == Box629{Any}(1)
            @test hash(Box629{Int}(1)) == hash(Box629{Any}(1))
        end

        @testset "Check that by default the hash function is stable after 1.7" begin
            # The value of `Base.hash(:x, UInt(0))` changed in 1.7, so it was already
            # unstable between 1.6 and 1.7.  Here we just add tests so that future
            # changes to the hash function will be observed.

            @auto_hash_equals struct Box1
                x
            end

            if VERSION < v"1.7"
                @test 0x67d66c8ebce604c4 === hash(Box1(1))
                @test 0x57ce10fa6d65774c === hash(Box1(:x))
                @test 0x7951851906420162 === hash(Box1("a"))
                @test 0x6a46c6ef41c6b97d === hash(Box1(1), UInt(1))
                @test 0x0ef668a2dd4500a0 === hash(Box1(:x), UInt(1))
                @test 0x7398684da66deba5 === hash(Box1("a"), UInt(1))
            else
                @test 0x05014b35fc91d289 === hash(Box1(1))
                @test 0x91d7652c7a24efb3 === hash(Box1(:x))
                @test 0x1d9ac96f957cc50a === hash(Box1("a"))
                @test 0x6e0378444e962be8 === hash(Box1(1), UInt(1))
                @test 0xa31a1cd3c72d944c === hash(Box1(:x), UInt(1))
                @test 0xe563b59c847e3d2f === hash(Box1("a"), UInt(1))
            end

            @auto_hash_equals struct Box2{T}
                x::T
            end

            if VERSION < v"1.7"
                @test 0x97e8e85cce6400e5 === hash(Box2(1))
                @test 0x97e8e85cce6400e5 === hash(Box2{Any}(1))
                @test 0x95c1c5ce8a9d4310 === hash(Box2(:x))
                @test 0x9424a3ad9ea0312c === hash(Box2("a"))
                @test 0xd7caed9a4e280b13 === hash(Box2(1), UInt(1))
                @test 0xd7caed9a4e280b13 === hash(Box2{Any}(1), UInt(1))
                @test 0x3c6236446852acfb === hash(Box2(:x), UInt(1))
                @test 0x08aaed0ddd68f482 === hash(Box2("a"), UInt(1))
            else
                @test 0xfddfe30b106aa2f0 === hash(Box2(1))
                @test 0xfddfe30b106aa2f0 === hash(Box2{Any}(1))
                @test 0xb9abdfa5883b32bb === hash(Box2(:x))
                @test 0x6c49b14653a071c6 === hash(Box2("a"))
                @test 0x451b0ebf9ee0f99c === hash(Box2(1), UInt(1))
                @test 0x451b0ebf9ee0f99c === hash(Box2{Any}(1), UInt(1))
                @test 0x175e9079609f34c5 === hash(Box2(:x), UInt(1))
                @test 0x77cf64ab93060d1e === hash(Box2("a"), UInt(1))
            end

            @auto_hash_equals struct Box3
                x
            end

            if VERSION < v"1.7"
                @test 0xa28c5530534e00ff === hash(Box3(1))
                @test 0xbd098dc8d84b2b3c === hash(Box3(:x))
                @test 0x306232d62b351152 === hash(Box3("a"))
                @test 0xd4f16da2b818329f === hash(Box3(1), UInt(1))
                @test 0xbc02b85a84d59f22 === hash(Box3(:x), UInt(1))
                @test 0xf3298984f3d3f10e === hash(Box3("a"), UInt(1))
            else
                @test 0x6c8a62ecebe7d0ce === hash(Box3(1))
                @test 0xb3dc0f774c8dbf65 === hash(Box3(:x))
                @test 0x18c77bdc2543b944 === hash(Box3("a"))
                @test 0x1fe5e7cdd29edab1 === hash(Box3(1), UInt(1))
                @test 0x55e8647bf53d5ecd === hash(Box3(:x), UInt(1))
                @test 0xf556f204c1f1bc53 === hash(Box3("a"), UInt(1))
            end

            @auto_hash_equals struct Box4{T}
                x::T
            end

            if VERSION < v"1.7"
                @test 0xa0164c66e926af40 === hash(Box4(1))
                @test 0xa0164c66e926af40 === hash(Box4{Any}(1))
                @test 0xcb0ce1b2da05840b === hash(Box4(:x))
                @test 0xc10479084e27e5db === hash(Box4("a"))
                @test 0xdbc4ab0260836c4a === hash(Box4(1), UInt(1))
                @test 0xdbc4ab0260836c4a === hash(Box4{Any}(1), UInt(1))
                @test 0x485f0ce7fd57b390 === hash(Box4(:x), UInt(1))
                @test 0xaff3b9595e40223d === hash(Box4("a"), UInt(1))
            else
                @test 0x98dc0cd9a86cbdee === hash(Box4(1))
                @test 0x98dc0cd9a86cbdee === hash(Box4{Any}(1))
                @test 0x3dbd99c859966133 === hash(Box4(:x))
                @test 0xa7d6e8579ef5a8cd === hash(Box4("a"))
                @test 0x44ac08ef000cb686 === hash(Box4(1), UInt(1))
                @test 0x44ac08ef000cb686 === hash(Box4{Any}(1), UInt(1))
                @test 0xc7dc8347992b452d === hash(Box4(:x), UInt(1))
                @test 0x3dcb6b6168a2c18d === hash(Box4("a"), UInt(1))
            end

        end

        @testset "ensure that type_seed(x) is stable" begin
            @test 0x4ae3767494b4cfaa === type_seed(Int)
            @test 0xb6c8f68810a16d66 === type_seed(String)

            @test 0x3215757a8995a661 === type_seed(G)
            @test 0x3215757a8995a661 === type_seed(G{T, U} where { T, U })
            @test 0xc6e6e47d689b8517 === type_seed(G{T, U} where { T <: Int, U <: String })
            @test 0xaa10d1f6a9b7e132 === type_seed(G{Int, String})
            @test 0xa740a4a4fc06d108 === type_seed(G{Int, T} where T)
            @test 0x7ab308cb793c5618 === type_seed(G{T, String} where T)
            @test 0xd02856316b177631 === type_seed(G{T, T} where T)
            @test 0xd02856316b177631 === type_seed(G{T, T} where T)
            @test 0xd3251f72348b86e2 === type_seed(G{G{T, Int}, G{T, String}} where T)
            @test 0xd3251f72348b86e2 === type_seed(G{G{T, Int}, G{T, String}} where T)

            @test 0x77f9d59da65a76bf === type_seed(Q)
            @test 0xb1241c9348842d51 === type_seed(B)
            @test 0xb1241c9348842d51 === type_seed(B{T} where { T })
            @test 0x9ae23988eb7c0716 === type_seed(B{T} where { T <: Int })
            @test 0xb3633f456e073d78 === type_seed(B{Int64})

            @test 0x5da6365f88849a43 === type_seed(Any)
            @test 0x3ea9a6632d35bdba === type_seed(Union{Int, String})
            @test 0x3cef2865f9232667 === type_seed(Union{})
            @test 0x7a86094a43978c16 === type_seed(Union)

            @test 0x29c3b5ce0a9c3a5b === type_seed(E)
            @test 0x00399c16f8744869 === type_seed(Tuple{})
            @test 0x00399c16f8744869 === type_seed(NTuple{0, Int})
            @test 0x808e1de371b0cce2 === type_seed(Tuple{String})
            @test 0x808e1de371b0cce2 === type_seed(NTuple{1, String})
            @test 0x899ca12a00ea1296 === type_seed(Tuple{String, Int})
            @test 0xf343d5b9c3ca4b77 === type_seed(@NamedTuple{a::Int, b::String})
            @test 0xf343d5b9c3ca4b77 === type_seed(typeof((a=1, b="")))
            @test 0xf7833397407626a0 === type_seed(typeof((a="", b=1)))
            @test 0xa4c046858bf076c3 === type_seed(NTuple{3, Int})
            @test 0x9977c31bb10d21bc === type_seed(Val{1})
            @test 0x19a63e87164d8e87 === type_seed(Val{:x})

            @test 0x789db08b2c84bf6c === type_seed(NTuple)
            @test 0x571b7e681184913a === type_seed(Tuple)
            @test hash(hash(1), UInt(0)) === type_seed(1)

            @test 0x9977c31bb10d21bc === type_seed(Val{1})
            @test 0xc19fa756b8cbf47d === type_seed(Val{:a})
            @test 0x7df4acaad2128daa === type_seed(Val{(1, :a)})
            @test 0xd5fb43db2f9427b4 === type_seed(Val{(1, :x)})
        end
    end

    @testset "test option typeseed=e" begin

        @testset "test typearg=true typeseed=hash generic type" begin
            @auto_hash_equals typearg=true typeseed=hash struct S640{T}
                w::T
            end
            @test hash(S640{Int}(1)) == hash(1, hash(S640{Int}))
            @test hash(S640{Int}(1), UInt(2)) == hash(1, UInt(2) + hash(S640{Int}))
        end

        @testset "test typearg=false typeseed=K generic type" begin
            @auto_hash_equals typearg=false typeseed=0x3dfe92e747bd4140 struct S642{T}
                w::T
            end
            @test hash(S642{Int}(1)) == hash(1, 0x3dfe92e747bd4140)
            @test hash(S642{Int}(1), UInt(2)) == hash(1, UInt(2) + 0x3dfe92e747bd4140)
        end

        @testset "test typearg=true typeseed=hash non-generic type" begin
            @auto_hash_equals typearg=true typeseed=hash struct S650
                w
            end
            @test hash(S650(1)) == hash(1, hash(S650))
            @test hash(S650(1), UInt(2)) == hash(1, UInt(2) + hash(S650))
        end

        @testset "test typearg=false typeseed=e non-generic type" begin
            @auto_hash_equals typearg=false typeseed=0x8dfd582f580f2e46 struct S658
                w
            end
            @test hash(S658(1)) == hash(1, 0x8dfd582f580f2e46)
            @test hash(S658(1), UInt(2)) == hash(1, UInt(2) + 0x8dfd582f580f2e46)
        end

        @testset "test using a constant for typeseed when a function is expected" begin
            @auto_hash_equals typearg=true typeseed=0x20cc10b97c7c95dd struct S674
                w
            end
            @test_throws MethodError hash(S674(1))
        end

        @testset "test using a function for typeseed when a constant is expected" begin
            @auto_hash_equals typearg=false typeseed=Base.hash struct S681
                w
            end
            @test_throws MethodError hash(S681(1))
        end


        @testset "== propogates missing, but `isequal` does not" begin
            # Fixed by https://github.com/JuliaServices/AutoHashEquals.jl/issues/18
            @auto_hash_equals struct Box18{T}
                x::T
            end
            ret = Box18(missing) == Box18(missing)
            @test ret === missing
            ret = Box18(missing) == Box18(1)
            @test ret === missing
            @test isequal(Box18(missing), Box18(missing))
            @test !isequal(Box18(missing), Box18(1))

            @auto_hash_equals struct Two18{T1, T2}
                x::T1
                y::T2
            end
            ret = Two18(1, missing) == Two18(1, 2)
            @test ret === missing

            ret = Two18(5, missing) == Two18(1, 2)
            @test ret === false

            ret = Two18(missing, 2) == Two18(1, 2)
            @test ret === missing

            ret = Two18(missing, 5) == Two18(1, 2)
            @test ret === false

            @auto_hash_equals mutable struct MutBox18{T}
                x::T
            end
            b = MutBox18(missing)
            ret = b == b
            @test ret === missing
            @test isequal(b, b)
        end

        @testset "test the compat1 flag" begin
            @auto_hash_equals struct Box890{T}
                x::T
            end
            @test ismissing(Box890(missing) == Box890(missing))
            @test isequal(Box890(missing), Box890(missing))
            @test ismissing(Box890(missing) == Box890(1))
            @test !isequal(Box890(missing), Box890(1))

            @auto_hash_equals compat1=true struct Box891{T}
                x::T
            end
            @test Box891(missing) == Box891(missing)
            @test isequal(Box891(missing), Box891(missing))
            @test Box891(missing) != Box891(1)
            @test !isequal(Box891(missing), Box891(1))
        end
    end
end

end # module
