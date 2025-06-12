defmodule DspexDemo.Signatures.SentimentSignature do
  @moduledoc """
  Analyze the sentiment of text with detailed classification.
  
  Classify text sentiment as positive, negative, or neutral with
  reasoning for the classification and confidence in the assessment.
  """
  
  use DSPEx.Signature, "text -> sentiment, reasoning, confidence"
end