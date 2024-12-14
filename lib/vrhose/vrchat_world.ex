defmodule VRHose.VRChatWorld do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias VRHose.Repo

  @type t :: %__MODULE__{}

  schema "vrchat_worlds" do
    field(:wrld_id, :string)
    field(:name, :string)
    field(:author_id, :string)
    field(:tags, :string)
    field(:capacity, :integer)
    field(:description, :string)
    timestamps(autogenerate: {VRHose.Data, :generate_unix_timestamp, []})
  end

  def one(wrld_id) do
    query = from(s in __MODULE__, where: s.wrld_id == ^wrld_id, select: s)
    Repo.replica(wrld_id).one(query, log: false)
  end

  def changeset(%__MODULE__{} = world, params) do
    world
    |> cast(params, [:wrld_id, :name, :author_id, :tags, :capacity, :description])
    |> validate_required([:wrld_id, :name, :author_id, :tags, :capacity, :description])
  end

  def insert(wrld_id, name, author_id, tags, capacity, description) do
    %__MODULE__{}
    |> changeset(%{
      wrld_id: wrld_id,
      name: name,
      author_id: author_id,
      tags: tags,
      capacity: capacity,
      description: description
    })
    |> Repo.insert()
  end

  def fetch(wrld_id) do
    maybe_world = one(wrld_id)

    if maybe_world == nil do
      {:ok, resp} = fetch_upstream(wrld_id)

      tags =
        resp.body["tags"]
        |> Enum.filter(fn tag ->
          String.starts_with?(tag, "content_")
        end)
        |> Jason.encode!()

      insert(
        resp.body["id"],
        resp.body["name"],
        resp.body["authorId"],
        tags,
        resp.body["capacity"],
        resp.body["description"]
      )
    else
      {:ok, maybe_world}
    end
  end

  defp fetch_upstream(wrld_id) do
    operator_email = System.get_env("VRHOSE_OPERATOR_EMAIL")

    if operator_email == nil do
      {:error, :no_operator_email}
    else
      Req.get("https://api.vrchat.cloud/api/1/worlds/#{wrld_id}",
        headers: [{"User-Agent", "BlueskyFirehoseVR/0.0.0 #{operator_email}"}]
      )
    end
  end
end
