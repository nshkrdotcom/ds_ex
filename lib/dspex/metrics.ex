defmodule DSPEx.Metrics do
  @moduledoc """
  Small collection of metric helpers for evaluation.
  """

  @doc """
  Exact match on a given field.
  """
  @spec exact_match(atom()) :: (map(), map() -> float())
  def exact_match(field) do
    fn example, outputs ->
      expected = fetch_field(example, field)
      actual = Map.get(outputs, field)
      if expected == actual, do: 1.0, else: 0.0
    end
  end

  @doc """
  Case-insensitive substring check.
  """
  @spec contains(atom()) :: (map(), map() -> float())
  def contains(field) do
    fn example, outputs ->
      expected = fetch_field(example, field)
      actual = Map.get(outputs, field)

      cond do
        is_binary(expected) and is_binary(actual) and
            String.contains?(String.downcase(actual), String.downcase(expected)) ->
          1.0

        expected == actual ->
          1.0

        true ->
          0.0
      end
    end
  end

  @doc """
  Simple token F1 (whitespace tokens).
  """
  @spec f1_tokens(atom()) :: (map(), map() -> float())
  def f1_tokens(field) do
    fn example, outputs ->
      expected = fetch_field(example, field)
      actual = Map.get(outputs, field)
      tokens_a = tokenize(expected)
      tokens_b = tokenize(actual)

      if tokens_a == [] or tokens_b == [] do
        0.0
      else
        tp = length(Enum.filter(tokens_b, &(&1 in tokens_a)))
        precision = tp / length(tokens_b)
        recall = tp / length(tokens_a)

        if precision + recall == 0 do
          0.0
        else
          2 * precision * recall / (precision + recall)
        end
      end
    end
  end

  @doc """
  ROUGE-1 style overlap ratio: |overlap| / |expected_tokens|.
  """
  @spec rouge1_overlap(atom()) :: (map(), map() -> float())
  def rouge1_overlap(field) do
    fn example, outputs ->
      expected = fetch_field(example, field)
      actual = Map.get(outputs, field)
      tokens_a = tokenize(expected)
      tokens_b = tokenize(actual)

      if tokens_a == [] do
        0.0
      else
        overlap = Enum.count(tokens_a, &(&1 in tokens_b))
        overlap / length(tokens_a)
      end
    end
  end

  @doc """
  Binary F1 on a boolean field (1 for match, 0 otherwise).
  """
  @spec f1_boolean(atom()) :: (map(), map() -> float())
  def f1_boolean(field) do
    fn example, outputs ->
      expected = fetch_field(example, field)
      actual = Map.get(outputs, field)

      case {expected, actual} do
        {true, true} -> 1.0
        {false, false} -> 1.0
        _ -> 0.0
      end
    end
  end

  defp fetch_field(%DSPEx.Example{} = example, field), do: DSPEx.Example.get(example, field)
  defp fetch_field(%{outputs: outputs}, field) when is_map(outputs), do: Map.get(outputs, field)
  defp fetch_field(map, field) when is_map(map), do: Map.get(map, field)
  defp fetch_field(_, _), do: nil

  defp tokenize(nil), do: []
  defp tokenize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
  end

  defp tokenize(other), do: to_string(other) |> tokenize()
end
