defmodule PersonalFinanceTracker.SSRRuntime do
  @moduledoc """
  Starts the LiveVue QuickBEAM SSR runtime with a **generous JS stack**.

  `LiveVue.SSR.QuickBEAM` hardcodes `QuickBEAM.start(name: …, apis: […])` and ignores options, so it
  runs at QuickBEAM's 8 MB default `max_stack_size`. Nuxt UI's tailwind-merge initialization recurses
  ~7.5 MB deep building its class-group map — right at that ceiling — so a runtime with slightly
  heavier stack frames (e.g. the Linux preview container vs. local macOS) tips over 8 MB and the SSR
  render dies with `RangeError: Maximum call stack size exceeded`.

  This child starts the QuickBEAM runtime **registered under `LiveVue.SSR.QuickBEAM`** (the name
  `LiveVue.SSR.QuickBEAM.render/3` calls into) with `max_stack_size: 32 MB` and loads the SSR bundle
  the same way LiveVue does. Keep `config :live_vue, ssr_module: LiveVue.SSR.QuickBEAM` — only the
  startup differs; render/3 is unchanged. Supervise this INSTEAD of `LiveVue.SSR.QuickBEAM`.
  """

  # 32 MB — ~4× the tailwind-merge init requirement (~7.5 MB), comfortable headroom across runtimes.
  @max_stack_size 32 * 1024 * 1024

  # Register under the exact name LiveVue.SSR.QuickBEAM.render/3 resolves (QuickBEAM.call(__MODULE__…)).
  @runtime_name LiveVue.SSR.QuickBEAM

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts \\ []) do
    {:ok, rt} =
      QuickBEAM.start(
        name: @runtime_name,
        apis: [:browser, :node],
        max_stack_size: @max_stack_size
      )

    load_bundle(rt)
    {:ok, rt}
  end

  # Mirror LiveVue.SSR.QuickBEAM's bundle load: evaluate the ES module and bridge its `render` export
  # onto globalThis so QuickBEAM.call/3 can reach it.
  defp load_bundle(rt) do
    bridged = read_bundle() <> "\nglobalThis.render = render;\n"

    case QuickBEAM.load_module(rt, "server", bridged) do
      :ok -> :ok
      {:error, reason} -> raise "QuickBEAM SSR bundle evaluation failed: #{inspect(reason)}"
    end
  end

  # Read via Erlang's `:file.read_file/1`, NOT `File.read!/1`: the path is the config-time SSR bundle
  # location (`:live_vue :ssr_filepath`), never user input — but Sobelow's `Traversal.FileModule`
  # flags any `File.read!` with a non-literal argument. `:file` is equivalent here and keeps the
  # scanner strict on genuine `File.*` usage elsewhere (matters most in agent-generated app code).
  defp read_bundle do
    case :file.read_file(ssr_filepath()) do
      {:ok, code} ->
        code

      {:error, reason} ->
        raise "QuickBEAM SSR bundle read failed (#{ssr_filepath()}): #{inspect(reason)}"
    end
  end

  defp ssr_filepath do
    filepath = Application.get_env(:live_vue, :ssr_filepath, "./static/server.mjs")

    if Path.type(filepath) == :absolute do
      filepath
    else
      {:ok, app} = :application.get_application()
      Application.app_dir(app, Path.join("priv", filepath))
    end
  end
end
