%{
  configs: [
    %{
      name: "default",
      plugins: [{AshCredo, []}],
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      # Disable AliasUsage — it nags about fully-qualified nested modules in test
      # setup/support (e.g. *.Support.* / Ecto.Adapters.SQL.Sandbox), which is fine there.
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []},
          # Intentional deferred-work markers; FIXME stays on.
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
