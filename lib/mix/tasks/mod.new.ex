defmodule Mix.Tasks.Mod.New do
  use Mix.Task
  import Modkit.TaskBase
  require Record
  alias Modkit.Templates

  @args_schema strict: [
                 gen_server: :boolean,
                 sup: :boolean
               ],
               aliases: [
                 s: :sup,
                 g: :gen_server
               ]

  def run(argv) do
    case OptionParser.parse(argv, @args_schema) do
      {_, [], []} ->
        abort("a module name is required")

      {opts, [name], []} ->
        Mix.Task.run("elixir.compile")
        opts = build_opts(opts)
        opts |> IO.inspect(label: "opts")
        do_run(name, opts)

      {_, _, invalid} ->
        abort("invalid options #{inspect(invalid)}")
    end
  end

  defp build_opts(opts) do
    Keyword.merge(default_opts(), opts)
  end

  defp default_opts do
    [gen_server: false, sup: false]
  end

  defp do_run(name, opts) do
    mount_points = get_mount_points()
    validate_name(name)
    split = String.split(name, ".")

    mount_point =
      Enum.find(mount_points, fn mnt(sprefix: prefix) -> List.starts_with?(split, prefix) end)

    if mount_point == nil do
      abort("no mount point found for #{name}")
    end

    mount_point |> IO.inspect(label: "mount_point")

    code = Templates.Module.get_code(%{name: name})
    code |> IO.inspect(label: "code")
    IO.puts(code)
  end

  @re_module ~r/^([A-Z][A-Za-z0-9_]*)(\.([A-Z][A-Za-z0-9_]*))*$/

  defp validate_name(name) do
    if not (name =~ @re_module) do
      abort("invalid module name #{name}")
    end
  end
end
