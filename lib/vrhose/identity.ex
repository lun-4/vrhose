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
    timestamps(autogenerate: {VRHose.Data, :generate_unix_timestamp, []})
  end

  def changeset(%__MODULE__{} = identity, params) do
    identity
    |> cast(params, [:did, :also_known_as, :atproto_pds_endpoint, :name])
    |> validate_required([:did, :also_known_as, :atproto_pds_endpoint, :name])
  end

  def one(did) do
    query = from(s in __MODULE__, where: s.did == ^did, select: s)
    Repo.replica(did).one(query, log: false)
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
    aka = String.downcase(aka)

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

  defmodule Janitor do
    require Logger

    import Ecto.Query
    alias VRHose.Identity
    alias VRHose.Repo.JanitorReplica

    def tick() do
      Logger.info("cleaning identities...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-1, :day)
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      deleted_count =
        from(s in Identity,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 1000
        )
        |> JanitorReplica.all()
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn identity ->
            Repo.delete(identity)
            1
          end)
          |> then(fn count ->
            :timer.sleep(1500)
            count
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} identities")
    end
  end
end
