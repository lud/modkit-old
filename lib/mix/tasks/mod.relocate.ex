defmodule Mix.Tasks.Mod.Relocate do
  use Mix.Task
  import Modkit.TaskBase

  require Record
  Record.defrecordp(:__mv, :move, mod: nil, cur_path: nil, good_path: nil, split: nil)

  @args_schema strict: [
                 force: :boolean
               ],
               aliases: [
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

  defp check_args(_, _opts) do
    :ok
  end

  defp get_modules(project, [] = _args, _opts) do
    otp_app = project_get(project, :app)

    case :application.get_key(otp_app, :modules) do
      {:ok, mods} -> {:ok, mods}
      :undefined -> {:error, "could not load app"}
    end
  end

  defp get_modules(_project, [mod], _opts) do
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
      get_mount_points(project)
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
          Enum.each(actions, &run_print/1)

          warn("""
          No actual action has been performed.
          Use the --force flag to make changes to the codebase.\
          """)

          abort("Some files are badly named. use the --force flag to perform changes.")
        end
    end
  end

  defp compute_actions(moves) do
    {actions, _} =
      Enum.flat_map_reduce(moves, %{}, fn move, dirs ->
        {dir_actions, dirs} = ensure_dirs(move, dirs)
        {dir_actions ++ [move], dirs}
      end)

    actions
  end

  defp ensure_dirs(__mv(good_path: path), dirs) do
    ensure_dirs(Path.dirname(path), [], dirs)
  end

  defp ensure_dirs(path, acc, dirs) when is_map_key(dirs, path) do
    {acc, dirs}
  end

  defp ensure_dirs(path, acc, dirs) do
    if File.dir?(path) do
      {acc, dirs}
    else
      acc = [{:mkdir, path} | acc]
      warn("register #{path}")
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
      magenta(bad_rest),
      "\n  -> ",
      common,
      "/",
      green(good_rest)
    ])
  end

  defp run_print({:mkdir, dir}) do
    print(["+dir ", cyan(dir)])
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

  defp deviate_path(from, to, []) do
    {".", Path.join(from), Path.join(to)}
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

  defp parent_mod_or_empty(all_mvs) do
    mvs = Enum.reject(all_mvs, &is_protocol_impl?/1)

    mvs
    |> Enum.find(fn __mv(split: split) ->
      Enum.all?(mvs, fn __mv(split: sub) -> List.starts_with?(sub, split) end)
    end)
    |> case do
      nil ->
        modules =
          Enum.map(mvs, &__mv(&1, :mod)) |> Enum.map(&" * #{inspect(&1)}") |> Enum.join("\n")

        warn("multiple modules defined in #{mvs |> hd |> __mv(:cur_path)}:\n#{modules}")
        []

      # __mv(mod: mod, cur_path: path) = mv ->
      mv ->
        # notice([
        #   "using #{inspect(mod)} as main module\nin: #{path}\nwith modules:\n",
        #   Enum.map_join([mv | mvs -- [mv]], "\n", &("  - " <> inspect(__mv(&1, :mod))))
        # ])

        [mv]
    end
  end

  defp is_protocol_impl?(__mv(mod: module)) do
    {:__impl__, 1} in module.module_info(:exports)
  end

  defp build_state(mod) do
    __mv(mod: mod, split: Module.split(mod))
  end

  defp mounted?(mv, mounts) when is_list(mounts) do
    Enum.any?(mounts, &mounted?(mv, &1))
  end

  defp mounted?(__mv(split: split), mnt(sprefix: prefix)) do
    List.starts_with?(split, prefix)
  end

  defp print_mount(mount) do
    mount
    |> Enum.map(fn mnt(namespace: mod, dir: path) ->
      ["mount ", cyan(inspect(mod)), " on ", cyan(path)]
    end)
    |> Enum.intersperse("\n")
    |> print()

    mount
  end

  defp with_source(__mv(mod: mod) = mv) do
    source = Keyword.fetch!(mod.module_info(:compile), :source) |> List.to_string()
    __mv(mv, cur_path: Path.relative_to_cwd(source))
  end

  defp with_dest(__mv(split: split) = mv, mount) do
    mnt(dir: mount_dir, flavor: flavor, sprefix: sprefix) =
      Enum.find(mount, fn mnt(sprefix: prefix) -> List.starts_with?(split, prefix) end)

    split_rest = unprefix(split, sprefix)

    segments =
      split_rest
      |> apply_flavor(flavor)
      |> Enum.map(&Macro.underscore/1)

    path = Path.join([mount_dir | segments]) <> ".ex"
    __mv(mv, good_path: path)
  end

  defp apply_flavor([], _) do
    []
  end

  defp apply_flavor(splits, :elixir) do
    splits
  end

  defp apply_flavor(splits, :phoenix) do
    last = List.last(splits)

    cond do
      String.ends_with?(last, "View") -> List.insert_at(splits, -2, "views")
      String.ends_with?(last, "Controller") -> List.insert_at(splits, -2, "controllers")
      String.ends_with?(last, "Channel") -> List.insert_at(splits, -2, "channels")
      String.ends_with?(last, "Socket") -> List.insert_at(splits, -2, "channels")
      :other -> splits
    end
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
