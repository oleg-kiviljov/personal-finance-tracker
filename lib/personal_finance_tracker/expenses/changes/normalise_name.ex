defmodule PersonalFinanceTracker.Expenses.Changes.NormaliseName do
  @moduledoc """
  Trims and downcases the `:name` attribute before persisting a `Category`.

  This keeps the `:unique_name` identity case-insensitive (so "Food" and "food" collide) without
  requiring the `citext` Postgres extension.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      name when is_binary(name) ->
        Ash.Changeset.change_attribute(changeset, :name, normalise(name))

      _ ->
        changeset
    end
  end

  @doc "Canonical category-name normalisation. Shared so seeds and the change can't diverge."
  @spec normalise(String.t()) :: String.t()
  def normalise(name) when is_binary(name), do: name |> String.trim() |> String.downcase()
end
