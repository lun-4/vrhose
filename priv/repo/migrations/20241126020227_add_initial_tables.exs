defmodule VRHose.Repo.Migrations.AddInitialTables do
  use Ecto.Migration

  def change do
    create table(:identity) do
      add(:did, :string)
      add(:also_known_as, :string, null: false)
      add(:atproto_pds_endpoint, :string, null: false)
      add(:name, :string)
      timestamps()
    end

    create(unique_index(:identity, [:did]))
  end
end
