defmodule VRHose.World do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias VRHose.Repo

  @type t :: %__MODULE__{}

  schema "worlds" do
    field(:vrchat_id, :string)
    field(:poster_did, :string)
    timestamps(autogenerate: {VRHose.Data, :generate_unix_timestamp, []})
  end

  def changeset(%__MODULE__{} = identity, params) do
    identity
    |> cast(params, [:vrchat_id, :poster_did])
    |> validate_required([:vrchat_id, :poster_did])
  end

  def last_worlds(count \\ 10) do
    query =
      from(s in __MODULE__,
        select: s,
        order_by: [desc: fragment("unixepoch(?)", s.inserted_at)],
        limit: ^count
      )

    Repo.all(query)
  end

  def insert(world_id, poster_did) do
    %__MODULE__{}
    |> changeset(%{
      vrchat_id: world_id,
      poster_did: poster_did
    })
    |> Repo.insert()
  end
end
