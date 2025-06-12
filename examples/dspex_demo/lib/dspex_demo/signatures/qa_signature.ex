defmodule DspexDemo.Signatures.QASignature do
  @moduledoc """
  Answer questions with reasoning and confidence.
  
  Provide clear, accurate answers to questions with step-by-step reasoning
  and a confidence score indicating how certain you are about the answer.
  """
  
  use DSPEx.Signature, "question -> answer, reasoning, confidence"
end