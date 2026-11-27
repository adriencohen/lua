defmodule Lua.TestTmpDir do
  @moduledoc false

  import ExUnit.Callbacks, only: [on_exit: 1]

  # The OS pid keeps concurrent `mix test` runs apart: `System.unique_integer/1`
  # repeats across BEAMs, and ExUnit's `@tag :tmp_dir` path depends only on the test name.
  @spec create_unique(map()) :: %{tmp_dir: Path.t()}
  def create_unique(%{module: test_module}) do
    path = Path.join(System.tmp_dir!(), "#{inspect(test_module)}-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{tmp_dir: path}
  end
end
