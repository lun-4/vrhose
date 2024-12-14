defmodule VRHose.Repo.Migrations.AddWorldLabels do
  use Ecto.Migration

  def change do
    create table(:vrchat_worlds) do
      add(:wrld_id, :text, null: false)
      add(:name, :text, null: false)
      add(:author_id, :text, null: false)
      add(:tags, :text, null: false)
      add(:capacity, :integer, null: false)
      add(:description, :text, null: false)
      timestamps()
    end

    create(unique_index(:vrchat_worlds, [:wrld_id]))
  end
end
