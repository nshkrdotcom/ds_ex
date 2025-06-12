#!/usr/bin/env elixir

defmodule TestSig do
  use DSPEx.Signature, "question -> answer"
end

IO.puts "Testing signature compilation..."
IO.inspect(TestSig.input_fields())
IO.inspect(TestSig.output_fields())