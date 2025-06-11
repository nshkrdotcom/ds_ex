defmodule DspexTest do
  use ExUnit.Case

  @moduletag :group_1
  doctest Dspex

  test "greets the world" do
    assert Dspex.hello() == :world
  end
end
