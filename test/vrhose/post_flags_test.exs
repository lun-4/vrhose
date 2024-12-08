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

  test "filters out post with just embed" do
    post =
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.external","external":{"uri":"https://youtube.com/shorts/jeRqbT6KU0w?si=EnjiH1_pnYhA1p72","thumb":{"$type":"blob","ref":{"$link":"bafkreihx4tdapw6zpt7fxgspswnfdpfeixmkupjollgdyn6zzq2sdq4dx4"},"mimeType":"image/jpeg","size":37954},"title":"Clip of Donald Trump Mocking a Disabled Person Resurfaces","description":"YouTube video by NowThis Impact"}},"langs":["en"],"createdAt":"2024-12-03T11:28:04.158Z"}
      """
      |> Jason.decode!()

    {_, accepted?} = VRHose.Ingestor.run_filters(post)
    assert not accepted?
  end
end
