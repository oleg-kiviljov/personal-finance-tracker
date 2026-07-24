# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is idempotent — safe to run repeatedly. Seeding is delegated to the Ash domain so tests and
# this script share one code path.

categories = PersonalFinanceTracker.Expenses.seed_default_categories()

IO.puts("Default categories present: #{Enum.map_join(categories, ", ", & &1.name)}")
