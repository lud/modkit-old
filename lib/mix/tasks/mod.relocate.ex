defmodule Mix.Tasks.Mod.Relocate do
  use Mix.Task
  import Modkit.TaskBase

  require Record
  Record.defrecordp(:__mv, :move, mod: nil, cur_path: nil, good_path: nil, split: nil)
  Record.defrecordp(:__mnt, :mount_point, namespace: nil, dir: nil, sprefix: nil)

  @args_schema strict: [
                 all: :boolean,
                 force: :boolean
               ],
               aliases: [
                 a: :all,
                 f: :force
               ]

  def run(argv) do
    case OptionParser.parse(argv, @args_schema) do
      {opts, args, []} ->
        Mix.Task.run("elixir.compile")
        opts = build_opts(opts)
        check_args(args, opts)
        do_run(args, opts)

      {_, _, invalid} ->
        abort("invalid options #{inspect(invalid)}")
    end
  end

  defp build_opts(opts) do
    Keyword.merge(default_opts(), opts)
  end

  defp default_opts do
    [all: false]
  end

  defp check_args([_, _ | _] = args, _opts) do
    abort("only one argument at most is expected, got: #{inspect(args)}")
  end

  defp check_args([_], opts) do
    if true == opts[:all] do
      abort("the --all option cannot be set when a module is provided")
    end
  end

  defp check_args([], opts) do
    if true != opts[:all] do
      abort("either a module or the --all option is required")
    end
  end

  defp get_modules(project, [] = _args, opts) do
    true = opts[:all]
    otp_app = project_get(project, :app)

    case :application.get_key(otp_app, :modules) do
      {:ok, mods} -> {:ok, mods}
      :undefined -> {:error, "could not load app"}
    end
  end

  defp get_modules(_project, [mod], opts) do
    false = opts[:all]

    mod =
      case mod do
        "Elixir." <> _ -> mod
        _ -> "Elixir." <> mod
      end
      |> String.to_atom()

    case Code.ensure_compiled(mod) do
      {:module, m} -> {:ok, [m]}
      {:error, reason} -> {:error, "could not find module #{inspect(mod)}: #{inspect(reason)}"}
    end
  end

  def do_run(args, opts) do
    project = Mix.Project.config()

    mount =
      project_get(project, [:modkit, :mount], default_mount(project))
      |> build_mount()
      |> print_mount()

    mods =
      case get_modules(project, args, opts) do
        {:ok, mods} -> mods
        {:error, errmsg} -> abort(errmsg)
      end

    moves =
      mods
      |> Enum.sort()
      |> Enum.map(&build_state/1)
      |> Enum.filter(&mounted?(&1, mount))
      |> Enum.map(fn mv -> mv |> with_source() |> with_dest(mount) end)
      |> discard_multis()
      |> Enum.filter(&bad_path?/1)
      |> Enum.filter(&can_move?/1)

    case compute_actions(moves) do
      [] ->
        success_stop("no action to perform")

      actions ->
        perform? = !!opts[:force]

        if perform? do
          Enum.each(actions, &run_move/1)
        else
          msgbox(
            "No actual action will be performed. use the --force flag to make changes to the codebase"
          )

          Enum.each(actions, &run_print/1)
          abort("Some files are badly named. use the --force flag to perform changes.")
        end
    end
  end

  defp compute_actions(moves) do
    {actions, _} =
      Enum.flat_map_reduce(moves, %{}, fn move, dirs ->
        {dir_actions, dirs} = ensure_dirs(move, dirs)
        {[move | dir_actions], dirs}
      end)

    :lists.reverse(actions)
  end

  defp ensure_dirs(__mv(good_path: path), dirs) do
    ensure_dirs(Path.dirname(path), [], dirs)
  end

  defp ensure_dirs(path, acc, dirs) when is_map_key(dirs, path) do
    {:lists.reverse(acc), dirs}
  end

  defp ensure_dirs(path, acc, dirs) do
    if File.dir?(path) do
      {:lists.reverse(acc), dirs}
    else
      acc = [{:mkdir, path} | acc]
      dirs = Map.put(dirs, path, true)
      ensure_dirs(Path.dirname(path), acc, dirs)
    end
  end

  defp run_print(__mv(cur_path: from, good_path: to)) do
    {common, bad_rest, good_rest} = deviate_path(from, to)

    print([
      "move ",
      common,
      "/",
      Owl.Tag.new(bad_rest, :magenta),
      "\n  -> ",
      common,
      "/",
      Owl.Tag.new(good_rest, :green)
    ])
  end

  defp run_print({:mkdir, dir}) do
    print(["+dir ", Owl.Tag.new(dir, :cyan)])
  end

  defp run_move(move) do
    run_print(move)

    case run_action(move) do
      :ok ->
        print("  => ok")

      {:error, reason} ->
        reason = ensure_string(reason)
        danger(["  => ", reason])
        abort(["action failed, other actions were aborted"])
    end
  end

  defp run_action(__mv(cur_path: from, good_path: to)) do
    File.rename(from, to)
  end

  defp run_action({:mkdir, dir}) do
    File.mkdir(dir)
  end

  defp deviate_path(from, to) do
    deviate_path(Path.split(from), Path.split(to), [])
  end

  defp deviate_path([same | from], [same | to], acc) do
    deviate_path(from, to, [same | acc])
  end

  defp deviate_path(from, to, acc) do
    {Path.join(:lists.reverse(acc)), Path.join(from), Path.join(to)}
  end

  defp discard_multis(states) do
    states
    |> Enum.group_by(fn __mv(cur_path: p) -> p end)
    |> Enum.flat_map(fn
      {_file, [single]} -> [single]
      {_file, multis} -> parent_mod_or_empty(multis)
    end)
  end

  defp parent_mod_or_empty(mvs) do
    Enum.find(mvs, fn __mv(split: split) ->
      Enum.all?(mvs, fn __mv(split: sub) -> List.starts_with?(sub, split) end)
    end)
    |> case do
      nil ->
        modules =
          Enum.map(mvs, &__mv(&1, :mod)) |> Enum.map(&" * #{inspect(&1)}") |> Enum.join("\n")

        warn("multiple modules defined in #{mvs |> hd |> __mv(:cur_path)}:\n#{modules}")
        []

      __mv(mod: mod, cur_path: path) = mv ->
        notice([
          "using #{inspect(mod)} as main module\nin: #{path}\nwith modules:\n",
          Enum.map_join([mv | mvs -- [mv]], "\n", &("  - " <> inspect(__mv(&1, :mod))))
        ])

        [mv]
    end
  end

  defp build_state(mod) do
    __mv(mod: mod, split: Module.split(mod))
  end

  defp mounted?(mv, mounts) when is_list(mounts) do
    Enum.any?(mounts, &mounted?(mv, &1))
  end

  defp mounted?(__mv(split: split), __mnt(sprefix: prefix)) do
    List.starts_with?(split, prefix)
  end

  defp default_mount(project) do
    [base_path | _] = project_get(project, :elixirc_paths)
    project_get(project, [])
    otp_app = project_get(project, :app)

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

  defp build_mount(points) do
    Enum.map(points, fn {mod, path} ->
      __mnt(namespace: mod, dir: path, sprefix: Module.split(mod))
    end)
  end

  defp print_mount(mount) do
    mount
    |> Enum.map(fn __mnt(namespace: mod, dir: path) ->
      ["mount ", Owl.Tag.new(inspect(mod), :cyan), " on ", Owl.Tag.new(path, :cyan)]
    end)
    |> Enum.intersperse("\n")
    |> msgbox()

    mount
  end

  defp with_source(__mv(mod: mod) = mv) do
    source = Keyword.fetch!(mod.module_info(:compile), :source) |> List.to_string()
    __mv(mv, cur_path: Path.relative_to_cwd(source))
  end

  defp with_dest(__mv(mod: mod, split: split) = mv, mount) do
    mount_point =
      Enum.find(mount, fn __mnt(sprefix: prefix) -> List.starts_with?(split, prefix) end)

    path = __mnt(mount_point, :dir)
    split_rest = unprefix(split, __mnt(mount_point, :sprefix))
    segments = Enum.map(split_rest, &Macro.underscore/1)
    path = Path.join([__mnt(mount_point, :dir) | segments]) <> ".ex"
    __mv(mv, good_path: path)
  end

  defp unprefix([same | mod_rest], [same | pref_rest]) do
    unprefix(mod_rest, pref_rest)
  end

  defp unprefix(mod_rest, []) do
    mod_rest
  end

  defp bad_path?(__mv(cur_path: same, good_path: same)), do: false
  defp bad_path?(_), do: true

  defp can_move?(__mv(mod: mod, good_path: path)) do
    if File.exists?(path) do
      warn("cannot move module #{inspect(mod)} to #{path}: file exists")
      false
    else
      true
    end
  end
end
