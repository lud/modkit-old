defmodule ModKitTest do
  use ExUnit.Case
  doctest ModKit

  test "greets the world" do
    assert ModKit.hello() == :world
  end
end
