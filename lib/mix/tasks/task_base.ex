defmodule Modkit.TaskBase do
  require Record
  Record.defrecord(:mnt, :mount_point, namespace: nil, dir: nil, sprefix: nil, flavor: :elixir)

  def project_get(mod, key_or_path) do
    _project_get(mod, key_or_path)
  rescue
    _ in KeyError -> abort("could not find #{inspect(key_or_path)} in project definition")
  end

  def project_get(mod, key_or_path, default) do
    _project_get(mod, key_or_path)
  rescue
    _ in KeyError -> default
  end

  defp _project_get(project, key) when is_atom(key) do
    project_get(project, [key])
  end

  defp _project_get(project, keys) when is_list(project) do
    fetch_in!(project, keys)
  end

  defp fetch_in!(data, []) do
    data
  end

  defp fetch_in!(data, [key | keys]) when is_list(data) do
    sub_data = Keyword.fetch!(data, key)
    fetch_in!(sub_data, keys)
  end

  def color(content, color),
    do: [apply(IO.ANSI, color, []), content, IO.ANSI.default_color()]

  def yellow(content), do: color(content, :yellow)
  def red(content), do: color(content, :red)
  def green(content), do: color(content, :green)
  def blue(content), do: color(content, :blue)
  def cyan(content), do: color(content, :cyan)
  def magenta(content), do: color(content, :magenta)

  def abort(iodata) do
    print(red(iodata))
    System.halt(1)
    Process.sleep(:infinity)
  end

  def success_stop(iodata) do
    success(iodata)
    System.halt()
    Process.sleep(:infinity)
  end

  def success(iodata) do
    print(green(iodata))
  end

  def danger(iodata) do
    print(red(iodata))
  end

  def warn(iodata) do
    print(yellow(iodata))
  end

  def notice(iodata) do
    print(magenta(iodata))
  end

  def print(iodata) do
    IO.puts(iodata)
  end

  def ensure_string(str) when is_binary(str) do
    str
  end

  def ensure_string(term) do
    inspect(term)
  end

  def build_mount(points) do
    Enum.map(points, fn {mod, point} ->
      {flavor, path} =
        case point do
          path when is_binary(path) -> {:elixir, path}
          {:phoenix, path} = fp when is_binary(path) -> fp
        end

      mnt(namespace: mod, dir: path, sprefix: Module.split(mod), flavor: flavor)
    end)
  end

  def get_mount_points do
    get_mount_points(Mix.Project.config())
  end

  def get_mount_points(project) do
    project
    |> project_get([:modkit, :mount], default_mount(project))
    |> build_mount()
  end

  defp default_mount(project) do
    [base_path | _] = project_get(project, :elixirc_paths)
    project_get(project, [])

    mix_mod =
      Mix.Project.get!()
      |> Module.split()
      |> :lists.reverse()
      |> case do
        ["MixProject" | rest] -> rest
      end
      |> :lists.reverse()
      |> Module.concat()

    mount_path = Path.join(base_path, Macro.underscore(mix_mod))
    [{mix_mod, mount_path}]
  end

  def unprefix([same | mod_rest], [same | pref_rest]) do
    unprefix(mod_rest, pref_rest)
  end

  def unprefix(mod_rest, []) do
    mod_rest
  end
end
