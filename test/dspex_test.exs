defmodule DspexTest do
  use ExUnit.Case

  @moduletag :phase_1
  doctest Dspex

  test "greets the world" do
    assert Dspex.hello() == :world
  end
end
