@auto_hash_equals struct PlainBox{T}
    value::T
end
@auto_hash_equals cache=true struct CachedBox{T}
    value::T
end
@auto_hash_equals typearg=true struct ParameterBox{T}
    value::T
end
@auto_hash_equals cache=true typearg=true struct CachedParameterBox{T}
    value::T
end

module SeedFirst
    struct Box{T}; value::T; end
end
module SeedSecond
    struct Box{T}; value::T; end
end

@testset "hash equality and collection lookup" begin
    for wrapper in (PlainBox, CachedBox, ParameterBox, CachedParameterBox)
        for value in (1, :x, "a", missing, NaN, -0.0, (1, :x), [1, 2])
            original = wrapper(value)
            restored = serialize_and_deserialize(original)
            @test isequal(original, restored)
            @test hash(original) == hash(restored)
            for seed in (UInt(0), UInt(1), typemax(UInt))
                @test hash(original, seed) == hash(restored, seed)
            end
            @test Dict(original => 42)[restored] == 42
            @test length(Set((original, restored))) == 1
        end
    end
    @test PlainBox{Int}(1) == PlainBox{Any}(1)
    @test hash(PlainBox{Int}(1)) == hash(PlainBox{Any}(1))
    @test CachedBox{Int}(1) == CachedBox{Any}(1)
    @test hash(CachedBox{Int}(1)) == hash(CachedBox{Any}(1))
    @test ParameterBox{Int}(1) != ParameterBox{Any}(1)
    @test CachedParameterBox{Int}(1) != CachedParameterBox{Any}(1)
end

@testset "type seeds preserve type structure" begin
    types = unique(Any[
        Int, String, G, G{T,U} where {T<:Int,U<:String}, G{Int,String},
        G{Int,T} where T, G{T,String} where T, G{T,T} where T,
        G{G{T,Int},G{T,String}} where T, Q, B, B{T} where {T<:Int},
        B{Int}, Any, Union{Int,String}, Union{}, Union, E, Tuple{},
        Tuple{String}, Tuple{String,Int}, NamedTuple{(:a,:b),Tuple{Int,String}},
        NamedTuple{(:a,:b),Tuple{String,Int}}, NTuple{3,Int}, Val{1}, Val{:x},
        Val{:a}, Val{(1,:a)}, Val{(1,:x)}, NTuple, Tuple,
        SeedFirst.Box{Int}, SeedSecond.Box{Int},
    ])
    @test length(unique(type_seed.(types))) == length(types)
    for typ in types
        restored = serialize_and_deserialize(typ)
        @test typ == restored
        @test type_seed(typ) == type_seed(restored)
    end
    @test type_seed(G) == type_seed(G{T,U} where {T,U})
    @test type_seed(Tuple{}) == type_seed(NTuple{0,Int})
    @test type_seed(Tuple{String}) == type_seed(NTuple{1,String})
    @test type_seed(Union{Int,String}) == type_seed(Union{String,Int})
    @test type_seed(NTuple) === 0x789db08b2c84bf6c
    @test type_seed(Tuple) === 0x571b7e681184913a
end
