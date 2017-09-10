"""
JSON writer serialization contexts.

This module defines the `Serialization` abstract type and several concrete
implementations, as they relate to JSON.
"""

module Serializations

using Compat
using ..Common

"""
A `Serialization` defines how objects are lowered to JSON format.
"""
@compat abstract type Serialization end

@compat abstract type CommonSerialization <: Serialization end
@doc """
The `CommonSerialization` comes with a default set of rules for serializing
Julia types to their JSON equivalents. Additional rules are provided either by
packages explicitly defining `JSON.show_json` for this serialization, or by the
`JSON.lower` method. Most concrete implementations of serializers should subtype
`CommonSerialization`, unless it is desirable to bypass the `lower` system, in
which case `Serialization` should be subtyped.
""" CommonSerialization

eval(Expr(Common.STRUCTHEAD, false, :(StandardSerialization <: CommonSerialization),
          quote end))
@doc """
The `StandardSerialization` defines a common, standard JSON serialization format
that is optimized to:

- strictly follow the JSON standard
- be useful in the greatest number of situations

All serializations defined for `CommonSerialization` are inherited by
`StandardSerialization`. It is therefore generally advised to add new
serialization behaviour to `CommonSerialization`.
""" StandardSerialization

end
