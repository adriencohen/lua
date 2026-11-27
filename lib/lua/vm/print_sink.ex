defmodule Lua.VM.PrintSink do
  @moduledoc """
  Where the `print` builtin sends each line, set per VM by the `:print` and
  `:max_print_output_bytes` options of `Lua.new/1`.

  Captured output is bounded by `max_bytes`, counting a newline per line. The
  first line that does not fit is dropped along with every later one, so the
  captured lines are always a prefix of what the script printed.
  """

  @default_max_bytes 1024 * 1024

  defstruct target: :stdout,
            max_bytes: @default_max_bytes,
            lines_newest_first: [],
            captured_bytes: 0,
            truncated: false

  @type target :: :capture | :stdout | (String.t() -> term())

  @type t :: %__MODULE__{
          target: target(),
          max_bytes: pos_integer() | :infinity,
          lines_newest_first: [String.t()],
          captured_bytes: non_neg_integer(),
          truncated: boolean()
        }

  @doc "The default bound on captured output, in bytes."
  @spec default_max_bytes() :: pos_integer()
  def default_max_bytes, do: @default_max_bytes

  @doc "An empty sink sending lines to `target`."
  @spec new(target(), pos_integer() | :infinity) :: t()
  def new(target, max_bytes), do: %__MODULE__{target: target, max_bytes: max_bytes}

  @doc "Sends one printed line to the sink's target."
  @spec write(t(), String.t()) :: t()
  def write(%__MODULE__{target: :capture, truncated: true} = sink, _line), do: sink

  def write(%__MODULE__{target: :capture} = sink, line) do
    capture(sink, line, sink.captured_bytes + byte_size(line) + 1)
  end

  def write(%__MODULE__{target: :stdout} = sink, line) do
    IO.puts(line)
    sink
  end

  def write(%__MODULE__{target: write_line} = sink, line) when is_function(write_line, 1) do
    write_line.(line)
    sink
  end

  @doc "The captured lines, oldest first."
  @spec lines(t()) :: [String.t()]
  def lines(%__MODULE__{lines_newest_first: lines_newest_first}), do: Enum.reverse(lines_newest_first)

  @doc "Empties the captured lines and lifts the truncation."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = sink), do: %{sink | lines_newest_first: [], captured_bytes: 0, truncated: false}

  # Every integer sorts below `:infinity`, so an unbounded sink captures every line.
  defp capture(%__MODULE__{max_bytes: max_bytes} = sink, line, captured_bytes_with_line)
       when captured_bytes_with_line <= max_bytes do
    %{sink | lines_newest_first: [line | sink.lines_newest_first], captured_bytes: captured_bytes_with_line}
  end

  defp capture(sink, _line, _captured_bytes_with_line), do: %{sink | truncated: true}
end
