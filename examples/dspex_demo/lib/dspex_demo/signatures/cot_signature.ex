defmodule DspexDemo.Signatures.CoTSignature do
  @moduledoc """
  Solve problems with explicit chain-of-thought reasoning.
  
  Break down complex problems into logical steps, showing your work
  clearly before arriving at the final answer.
  """
  
  use DSPEx.Signature, "problem -> reasoning, answer"
end