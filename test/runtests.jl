# SPDX-License-Identifier: MIT

module runtests

using AutoHashEquals: @auto_hash_equals
using Markdown: plain
using Match: Match, @match, MatchFailure
using Random
using Serialization
using Test

function serialize_and_deserialize(x)
    buf = IOBuffer()
    serialize(buf, x)
    seekstart(buf)
    deserialize(buf)
end

macro noop(x)
    esc(quote
       Base.@__doc__$(x)
    end)
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
            @test hash(T35()) == hash(T35)
            @test hash(T35(), UInt(0)) == hash(hash(T35), UInt(0))
            @test hash(T35(), UInt(1)) == hash(hash(T35), UInt(1))
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
            @test hash(T48(1, :x)) == hash(:x,hash(1,hash(T48)))
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
            @auto_hash_equals_cached struct T63{G}
                x
                y::G
            end
            @test T63{Symbol}(1, :x) isa T63
            @test hash(T63{Symbol}(1, :x)) == hash(:x,hash(1,hash(T63{Symbol})))
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
            @auto_hash_equals_cached struct T107a{T}<:Base107{T} x::T end
            @auto_hash_equals_cached struct T107b{T}<:Base107{T} x::T end
            @test T107a(1) isa T107a
            @test T107a(1) == T107a(1)
            @test T107a(1) == serialize_and_deserialize(T107a(1))
            @test T107a(1) != T107a(2)
            @test hash(T107a(1)) == hash(1, hash(T107a{Int}))
            @test hash(T107a("x")) == hash("x", hash(T107a{String}))
            @test hash(T107a(1)) != hash(T107b(1))
            @test hash(T107a(1)) != hash(T107a(2))
        end

        @testset "macro applied to type before @auto_hash_equals_cached" begin
            @noop @auto_hash_equals_cached struct T116
                x::Int
                y
            end
            @test T116(1, :x) isa T116
            @test hash(T116(1, :x)) == hash(:x,hash(1,hash(T116)))
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
            @test hash(T132(1, :x)) == hash(:x,hash(1,hash(T132)))
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
            @test hash(T135(1, :x)) == hash(:x,hash(1,hash(T135)))
            @test T135(1, :x) == T135(1, :x)
            @test T135(1, :x) != T135(2, :x)
            @test hash(T135(1, :x)) != hash(T135(2, :x))
            @test T135(1, :x) != T135(1, :y)
            @test hash(T135(1, :x)) != hash(T135(1, :y))
            @test T135(1, :x) == serialize_and_deserialize(T135(1, :x))
            @test hash(T135(1, :x)) == hash(serialize_and_deserialize(T135(1, :x)))
        end

        @testset "contained NaN values compare equal" begin
            @auto_hash_equals_cached struct T140
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test T140(nan) == T140(nan)
        end

        @testset "ensure circular data structures, produced by hook or by crook, do not blow the stack" begin
            @auto_hash_equals_cached struct T145
                a::Array{Any,1}
            end
            t::T145 = T145(Any[1])
            t.a[1] = t
            @test hash(t) != 0
            @test t == t
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
            @auto_hash_equals struct T201{G}
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
            @auto_hash_equals struct T225a{T}<:Base225{T} x::T end
            @auto_hash_equals struct T225b{T}<:Base225{T} x::T end
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

        @testset "contained NaN values compare equal" begin
            @auto_hash_equals struct T330
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test T330(nan) == T330(nan)
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

    end
end

end # module
