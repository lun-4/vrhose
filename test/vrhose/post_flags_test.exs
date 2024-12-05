defmodule VRHose.PostFlagsTest do
  use ExUnit.Case

  test "works on embed" do
    post =
      """
      {"text":"Convinced me","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreiczor6cyu2ar6aftgrdsmtgntj42uvvusmvnuz2kyiy7x35wb5s7u","uri":"at://did:plc:kbfrbbdkkw5l6g6isuxyqrje/app.bsky.feed.post/3lcf5dluaqc23"}},"langs":["en"],"createdAt":"2024-12-03T10:37:25.131Z"}
      """
      |> Jason.decode!()

    flags = VRHose.Ingestor.post_flags_for(post)
    assert String.contains?(flags, "q")
  end
end
