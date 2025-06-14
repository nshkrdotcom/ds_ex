## 10. **NEW: Predictor Mapping System**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.PredictorMapping do
  @moduledoc """
  System for building and managing predictor mappings for program introspection.
  
  This module analyzes programs to extract predictors and create bidirectional
  mappings between predictor names and actual predictor instances.
  """
  
  alias DSPEx.Program
  
  @type predictor_info :: %{
    name: String.t(),
    type: atom(),
    signature: any(),
    instructions: String.t() | nil,
    metadata: map()
  }
  
  @type predictor_mappings :: {
    predictor_to_name :: %{any() => String.t()},
    name_to_predictor :: %{String.t() => any()}
  }
  
  @spec build_predictor_mappings(Program.t()) :: predictor_mappings()
  def build_predictor_mappings(program) do
    predictors = extract_predictors_from_program(program)
    
    predictor_to_name = predictors
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {{predictor, info}, index}, acc ->
        name = generate_predictor_name(info, index)
        Map.put(acc, predictor, name)
      end)
    
    name_to_predictor = predictor_to_name
      |> Enum.reduce(%{}, fn {predictor, name}, acc ->
        Map.put(acc, name, predictor)
      end)
    
    {predictor_to_name, name_to_predictor}
  end
  
  @spec extract_predictors_from_program(Program.t()) :: [{any(), predictor_info()}]
  defp extract_predictors_from_program(program) do
    case program do
      # ChainOfThought program
      %{predictors: predictors} when is_list(predictors) ->
        predictors
        |> Enum.with_index()
        |> Enum.map(fn {predictor, index} ->
          info = analyze_predictor(predictor, "step_#{index}")
          {predictor, info}
        end)
      
      # Single predictor program
      %{predictor: predictor} when not is_nil(predictor) ->
        info = analyze_predictor(predictor, "main")
        [{predictor, info}]
      
      # OptimizedProgram wrapper
      %DSPEx.OptimizedProgram{program: inner_program} ->
        extract_predictors_from_program(inner_program)
      
      # Try to introspect the program structure
      _ ->
        introspect_program_predictors(program)
    end
  end
  
  @spec analyze_predictor(any(), String.t()) :: predictor_info()
  defp analyze_predictor(predictor, default_name) do
    signature = extract_signature(predictor)
    instructions = extract_instructions(predictor)
    predictor_type = determine_predictor_type(predictor)
    
    %{
      name: default_name,
      type: predictor_type,
      signature: signature,
      instructions: instructions,
      metadata: %{
        has_signature: not is_nil(signature),
        has_instructions: not is_nil(instructions),
        extracted_at: DateTime.utc_now()
      }
    }
  end
  
  defp extract_signature(predictor) do
    cond do
      is_map(predictor) and Map.has_key?(predictor, :signature) ->
        predictor.signature
      
      function_exported?(predictor, :signature, 0) ->
        try do
          predictor.signature()
        rescue
          _ -> nil
        end
      
      true ->
        nil
    end
  end
  
  defp extract_instructions(predictor) do
    signature = extract_signature(predictor)
    
    cond do
      is_nil(signature) ->
        nil
      
      function_exported?(signature, :instructions, 0) ->
        try do
          signature.instructions()
        rescue
          _ -> nil
        end
      
      is_map(signature) and Map.has_key?(signature, :instructions) ->
        signature.instructions
      
      true ->
        nil
    end
  end
  
  defp determine_predictor_type(predictor) do
    cond do
      is_map(predictor) and Map.has_key?(predictor, :__struct__) ->
        predictor.__struct__
        |> Module.split()
        |> List.last()
        |> String.downcase()
        |> String.to_atom()
      
      is_function(predictor) ->
        :function
      
      is_atom(predictor) ->
        :module
      
      true ->
        :unknown
    end
  end
  
  defp introspect_program_predictors(program) do
    # Try to find predictor-like fields through introspection
    program_fields = if is_map(program) do
      Map.keys(program)
    else
      []
    end
    
    predictor_fields = Enum.filter(program_fields, fn field ->
      field_name = to_string(field)
      String.contains?(field_name, "predict") or 
      String.contains?(field_name, "forward") or
      String.contains?(field_name, "generate")
    end)
    
    predictor_fields
    |> Enum.map(fn field ->
      predictor = Map.get(program, field)
      info = analyze_predictor(predictor, to_string(field))
      {predictor, info}
    end)
  end
  
  defp generate_predictor_name(info, index) do
    base_name = case info.type do
      :chainofthought -> "cot"
      :generate -> "gen"
      :predict -> "pred"
      :classify -> "cls"
      _ -> "pred"
    end
    
    if info.metadata.has_signature and not is_nil(info.instructions) do
      instruction_summary = info.instructions
        |> String.split()
        |> Enum.take(3)
        |> Enum.join("_")
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]/, "")
      
      "#{base_name}_#{index}_#{instruction_summary}"
    else
      "#{base_name}_#{index}"
    end
  end
  
  @spec find_predictor_by_name(predictor_mappings(), String.t()) :: any() | nil
  def find_predictor_by_name({_predictor_to_name, name_to_predictor}, name) do
    Map.get(name_to_predictor, name)
  end
  
  @spec find_name_by_predictor(predictor_mappings(), any()) :: String.t() | nil
  def find_name_by_predictor({predictor_to_name, _name_to_predictor}, predictor) do
    Map.get(predictor_to_name, predictor)
  end
  
  @spec list_all_predictors(predictor_mappings()) :: [String.t()]
  def list_all_predictors({_predictor_to_name, name_to_predictor}) do
    Map.keys(name_to_predictor)
  end
end
```
