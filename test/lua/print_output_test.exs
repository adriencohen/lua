defmodule Lua.PrintOutputTest do
  @moduledoc "Pins where `print` sends its output: stdout by default, `:capture` and function sinks as opt-ins."

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @forged_log_line ~S|print("x\n[error] fake log line", 1, 2)|

  test "a default VM writes print output to stdout" do
    {lua, stdout} = with_io(fn -> lua_after_eval!(Lua.new(), @forged_log_line) end)

    assert stdout == "x\n[error] fake log line\t1\t2\n"
    assert Lua.print_output(lua) == []
  end

  test "print: :capture writes nothing to stdout and keeps the line for the host" do
    {lua, stdout} = with_io(fn -> lua_after_eval!(Lua.new(print: :capture), @forged_log_line) end)

    assert stdout == ""
    assert Lua.print_output(lua) == ["x\n[error] fake log line\t1\t2"]
  end

  test "print: a function receives each line as it is printed" do
    test_pid = self()
    lua = Lua.new(print: &send(test_pid, {:printed, &1}))

    assert_raise Lua.RuntimeException, ~r/boom/, fn ->
      Lua.eval!(lua, ~S[print("before", 1) error("boom")])
    end

    assert_received {:printed, "before\t1"}
  end

  test "capture stops at :max_print_output_bytes and reports the truncation" do
    lua = Lua.new(print: :capture, max_print_output_bytes: 10)

    assert {["done"], lua} =
             Lua.eval!(lua, ~S"""
             for i = 1, 1000 do print("line", i) end
             return "done"
             """)

    assert Lua.print_output(lua) == ["line\t1"]
    assert Lua.print_output_truncated?(lua)
  end

  test "clear_print_output/1 empties the capture and lifts the truncation" do
    lua = lua_after_eval!(Lua.new(print: :capture, max_print_output_bytes: 8), ~S[print("short") print("dropped")])

    cleared = Lua.clear_print_output(lua)

    assert Lua.print_output(cleared) == []
    refute Lua.print_output_truncated?(cleared)
    assert Lua.print_output(lua_after_eval!(cleared, ~S[print("again")])) == ["again"]
  end

  test "a print line longer than :max_string_bytes raises the catchable error" do
    lua = Lua.new(print: :capture, max_string_bytes: 16)

    assert {[false, message], lua} =
             Lua.eval!(lua, ~S[return pcall(print, string.rep("x", 10), string.rep("y", 10))])

    assert message =~ "resulting string too large"
    assert Lua.print_output(lua) == []
  end

  test "lines printed before a caught error are kept" do
    lua = lua_after_eval!(Lua.new(print: :capture), ~S[pcall(function() print("before") error("boom") end)])

    assert Lua.print_output(lua) == ["before"]
  end

  test "a host-defined print replaces the builtin and its sink" do
    test_pid = self()

    lua =
      Lua.set!(Lua.new(print: :capture), [:print], fn args ->
        send(test_pid, {:host_print, args})
        []
      end)

    {lua, stdout} = with_io(fn -> lua_after_eval!(lua, ~S[print("hi", 2)]) end)

    assert_received {:host_print, ["hi", 2]}
    assert stdout == ""
    assert Lua.print_output(lua) == []
  end

  defp lua_after_eval!(lua, source) do
    {_results, lua} = Lua.eval!(lua, source)
    lua
  end
end
