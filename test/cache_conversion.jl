@auto_hash_equals cache=true struct RoundedBox{T}
    value::T
end
@auto_hash_equals cache=true typearg=true struct RoundedParameterBox{T<:AbstractFloat}
    value::T
end
@auto_hash_equals cache=true struct FixedRoundedBox
    value::Float32
end
@auto_hash_equals cache=true fields=(value,tag) struct ConvertedFieldsBox
    value::Float32
    tag::Int8
    ignored::Float32
end
@auto_hash_equals cache=true struct ConstructorNameBox
    ConstructorNameBox::Float32
end
integer_hash(value) = Int32(7)
integer_hash(value, seed) = Int32(7)
@auto_hash_equals cache=true hashfn=integer_hash struct IntegerHashBox
    value::Int
end

struct ConversionInput
    value::Float64
end
struct ConversionStored
    value::Float32
end
struct BadConversionInput end
const conversion_count = Ref(0)
Base.convert(::Type{ConversionStored}, input::ConversionInput) =
    (conversion_count[] += 1; ConversionStored(input.value))
Base.convert(::Type{ConversionStored}, input::ConversionStored) =
    (conversion_count[] += 100; input)
Base.convert(::Type{ConversionStored}, ::BadConversionInput) = "wrong field type"
Base.hash(::ConversionInput, ::UInt) = error("hash must receive the stored value")
Base.hash(::BadConversionInput, ::UInt) = error("hash must follow successful conversion")
Base.hash(value::ConversionStored, seed::UInt) = hash(value.value, seed)
Base.isequal(first::ConversionStored, second::ConversionStored) = isequal(first.value, second.value)
Base.:(==)(first::ConversionStored, second::ConversionStored) = first.value == second.value

struct PlainConvertedBox
    value::ConversionStored
end
@auto_hash_equals cache=true struct CachedConvertedBox
    value::ConversionStored
end
converted_hash(value) = hash(value)
converted_hash(value, seed::UInt) = hash(value, seed)
@auto_hash_equals cache=true hashfn=converted_hash struct CustomConvertedBox
    value::ConversionStored
end

@testset "cached hashes follow field conversion" begin
    for wrapper in (RoundedBox{Float32}, RoundedParameterBox{Float32}, FixedRoundedBox)
        first = wrapper(1.0)
        rounded = wrapper(1.0 + eps())
        @test first.value === rounded.value === 1.0f0
        @test first == rounded
        @test isequal(first, rounded)
        @test hash(first) == hash(rounded)
        for seed in (UInt(0), UInt(1), typemax(UInt))
            @test hash(first, seed) == hash(rounded, seed)
        end
        @test get(Dict(first => 42), rounded, nothing) === 42
        @test length(Set((first, rounded))) == 1
        @test isequal(first, serialize_and_deserialize(rounded))
    end

    first = ConvertedFieldsBox(1.0, 2.0, 3.0)
    rounded = ConvertedFieldsBox(1.0 + eps(), Int16(2), 4.0)
    @test first.value === rounded.value === 1.0f0
    @test first.tag === rounded.tag === Int8(2)
    @test first.ignored === 3.0f0
    @test rounded.ignored === 4.0f0
    @test first == rounded
    @test isequal(first, rounded)
    @test hash(first) == hash(rounded)
    @test Dict(first => 42)[rounded] == 42
    @test_throws InexactError ConvertedFieldsBox(1, 2.5, 3)
    @test ConstructorNameBox(1.0).ConstructorNameBox === 1.0f0
    @test ConstructorNameBox(1.0) == ConstructorNameBox(1.0 + eps())
    @test hash(ConstructorNameBox(1.0)) == hash(ConstructorNameBox(1.0 + eps()))
    @test hash(IntegerHashBox(1)) === UInt(7)

    for wrapper in (CachedConvertedBox, CustomConvertedBox)
        for input in (ConversionInput(1.0 + eps()), ConversionStored(1.0f0))
            conversion_count[] = 0
            plain = PlainConvertedBox(input)
            plain_count = conversion_count[]
            conversion_count[] = 0
            cached = wrapper(input)
            @test conversion_count[] == plain_count
            @test plain.value == cached.value
            @test cached == wrapper(ConversionStored(1.0f0))
            @test hash(cached) == hash(wrapper(ConversionStored(1.0f0)))
        end
        @test_throws TypeError PlainConvertedBox(BadConversionInput())
        @test_throws TypeError wrapper(BadConversionInput())
    end
end
