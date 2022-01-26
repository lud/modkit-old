defmodule Modkit.TaskBase do
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

  def abort(errmsg) do
    Owl.IO.puts(Owl.Tag.new(errmsg, :red))
    System.halt(1)
    Process.sleep(:infinity)
  end

  def success_stop(errmsg) do
    success(errmsg)
    System.halt()
    Process.sleep(:infinity)
  end

  def success(errmsg) do
    Owl.IO.puts(Owl.Tag.new(errmsg, :green))
  end

  def danger(errmsg) do
    Owl.IO.puts(Owl.Tag.new(errmsg, :red))
  end

  def warn(errmsg) do
    Owl.IO.puts(Owl.Tag.new(errmsg, :yellow))
  end

  def notice(errmsg) do
    Owl.IO.puts(Owl.Tag.new(errmsg, :magenta))
  end

  def print(errmsg) do
    Owl.IO.puts(errmsg)
  end

  def msgbox(message, opts \\ []) do
    opts = Keyword.merge(default_box_opts(), opts)

    message
    |> Owl.Box.new(opts)
    |> Owl.IO.puts()
  end

  defp default_box_opts do
    [
      padding_right: 1,
      padding_left: 1
    ]
  end

  def ensure_string(str) when is_binary(str) do
    str
  end

  def ensure_string(term) do
    inspect(term)
  end
end
