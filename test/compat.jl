module compat

using AutoHashEquals.Compat: @auto_hash_equals
using Test

@testset "test the compat macro" begin
    @auto_hash_equals struct Box851{T}
        x::T
    end
    @test Box851(missing) == Box851(missing)
    @test isequal(Box851(missing), Box851(missing))
    @test Box851(missing) != Box851(1)
    @test !isequal(Box851(missing), Box851(1))
end

end
