defmodule VRHose.Repo.Migrations.AddWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds) do
      add(:vrchat_id, :text, null: false)
      add(:poster_did, :text, null: false)
      timestamps()
    end

    create(index(:worlds, ["unixepoch(inserted_at)"]))
  end
end
