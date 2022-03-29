defmodule Modkit.Templates.Module do
  def get_code(%{name: name} = vars) do
    %{uses: uses, defs: defs} = with_defaults(vars)

    """
    defmodule #{name} do
      #{if vars[:uses], do: format_uses(vars), else: ""}
    end
    """
    |> Code.format_string!(get_formatter_opts())
    |> :erlang.iolist_to_binary()
  end

  defp format_uses(%{uses: uses}) do
    uses
    |> Enum.sort()
    |> Enum.map_join("\n", fn mod ->
      "use " <> inspect(mod)
    end)
  end

  defp with_defaults(vars) do
    Map.merge(defaults(), vars)
  end

  defp defaults do
    %{uses: nil, defs: nil}
  end

  defp get_formatter_opts do
    path = File.cwd!() |> Path.join(".formatter.exs")
    {opts, _} = Code.eval_file(path)
    opts
  rescue
    _ -> []
  end
end
