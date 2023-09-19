module Compat

using AutoHashEquals: AutoHashEquals

export @auto_hash_equals

"""
    @auto_hash_equals [options] struct Foo ... end

Generate `Base.hash`, `Base.isequal`, and `Base.==` methods for `Foo`.

Options:

* `cache=true|false` whether or not to generate an extra cache field to store the precomputed hash value. Default: `false`.
* `hashfn=myhash` the hash function to use. Default: `Base.hash`.
* `fields=a,b,c` the fields to use for hashing and equality. Default: all fields.
* `typearg=true|false` whether or not to make type arguments significant. Default: `false`.
* `typeseed=e` Use `e` (or `e(type)` if `typearg=true`) as the seed for hashing type arguments.
* `compat1=true` To have `==` defined by using `isequal`.  Default: `true`.
"""
macro auto_hash_equals(args...)
    esc(:($AutoHashEquals.@auto_hash_equals(compat1=true, $(args...))))
end

end
