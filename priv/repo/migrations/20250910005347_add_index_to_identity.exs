defmodule VRHose.Repo.Migrations.AddIndexToIdentity do
  use Ecto.Migration

  def change do
    create(index(:identity, ["unixepoch(inserted_at)"]))
  end
end
