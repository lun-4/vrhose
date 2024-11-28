defmodule VRHose.Identity do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias VRHose.Repo

  @type t :: %__MODULE__{}

  schema "identity" do
    field(:did, :string)
    field(:also_known_as, :string)
    field(:atproto_pds_endpoint, :string)
    field(:name, :string)
    timestamps()
  end

  def changeset(%__MODULE__{} = identity, params) do
    identity
    |> cast(params, [:did, :also_known_as, :atproto_pds_endpoint, :name])
    |> validate_required([:did, :also_known_as, :atproto_pds_endpoint, :name])
  end

  def one(did) do
    query = from(s in __MODULE__, where: s.did == ^did, select: s)
    Repo.one(query, log: false)
  end

  def fake(did) do
    %__MODULE__{
      did: did,
      also_known_as: did,
      atproto_pds_endpoint: "no",
      name: did
    }
  end

  def insert(did, aka, atproto_pds_endpoint, name) do
    %__MODULE__{}
    |> changeset(%{
      did: did,
      also_known_as: aka,
      atproto_pds_endpoint: atproto_pds_endpoint,
      name: name
    })
    |> Repo.insert(
      on_conflict: [
        set: [
          did: did,
          also_known_as: aka,
          atproto_pds_endpoint: atproto_pds_endpoint,
          name: name
        ]
      ],
      log: false
    )
  end
end
