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

    {_, filtered?} = VRHose.Ingestor.run_filters(post)
    assert filtered?
  end

  test "filters out these posts i think" do
    posts_to_filter = [
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.recordWithMedia","media":{"$type":"app.bsky.embed.images","images":[{"alt":"","image":{"$type":"blob","ref":{"$link":"bafkreiboaz6mjvtaw2nv2d6plixlc6w4c3mkzractx4klzwbmw7go56a6e"},"mimeType":"image/jpeg","size":544839},"aspectRatio":{"width":934,"height":931}},{"alt":"","image":{"$type":"blob","ref":{"$link":"bafkreidk37e7uecrekovsm3pxdbgkuovimswvyk67kd2yb4oxicat3efny"},"mimeType":"image/jpeg","size":487014},"aspectRatio":{"width":750,"height":945}},{"alt":"","image":{"$type":"blob","ref":{"$link":"bafkreigzkjdviuo4plac6ccx56d3uamw3ym5tve336tp23ln6dzqlhktju"},"mimeType":"image/jpeg","size":74021},"aspectRatio":{"width":960,"height":736}},{"alt":"","image":{"$type":"blob","ref":{"$link":"bafkreicvoonwjowxyr4io67zi5237cxmpymr5opnduc62dfqvgwmb4ru34"},"mimeType":"image/jpeg","size":162080},"aspectRatio":{"width":960,"height":887}}]},"record":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreia3e4orqipmnbrznrml5bjdllwsjtccaqd5ii7jqvpn6z5tjmik7u","uri":"at://did:plc:vowtbiwp2g2rqsq3ftrv6gqz/app.bsky.feed.post/3ld2e45ecl222"}}},"langs":["en"],"createdAt":"2024-12-14T04:49:25.192Z"}
      """,
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.recordWithMedia","media":{"$type":"app.bsky.embed.external","external":{"uri":"https://open.spotify.com/album/5hzSssDOGvtV8LtqHDdoDS?si=IyOLfdTGQlW6Pre2fcGLxg","thumb":{"$type":"blob","ref":{"$link":"bafkreiebiydw5yekm2rlsrdlatqhkvay7bzorecegotohqjexi5jgz3bdy"},"mimeType":"image/jpeg","size":277394},"title":"Xeno","description":"Santino Le Saint · EP · 2018 · 3 songs"}},"record":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreiegqnwmxhb4lraxccmgsp7bf4w7xm4y47x2yob7igtkxfmw2imc7a","uri":"at://did:plc:rqehws5hhimzu47hkjal7i5w/app.bsky.feed.post/3ld4lmfer722e"}}},"langs":["en"],"createdAt":"2024-12-14T05:00:18.373Z"}
      """,
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.recordWithMedia","media":{"$type":"app.bsky.embed.external","external":{"uri":"https://media.tenor.com/WB_3sRiDCiAAAAAC/lonely-island-the-creep.gif?hh=280&ww=498","thumb":{"$type":"blob","ref":{"$link":"bafkreifl6wnsejq3m7lguxpwtwgywbjanmodbquecp4b63jvijph5t6t2m"},"mimeType":"image/jpeg","size":102167},"title":"Lonely Island The Creep GIF","description":"ALT: Lonely Island The Creep GIF"}},"record":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreifjiprcysvxoiko2vo7uknboosj232bzwlno2bbeztbj37tiwzt7m","uri":"at://did:plc:egiwo4lte2phjkajxjd4a4ba/app.bsky.feed.post/3ldae4tez5k2x"}}},"langs":["en"],"createdAt":"2024-12-14T05:02:00.713Z"}
      """,
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.recordWithMedia","media":{"$type":"app.bsky.embed.video","video":{"$type":"blob","ref":{"$link":"bafkreihigop2xzvlktxcfjajihrfuvyuybhkofeiyzlr7xf2kr7onmr72e"},"mimeType":"video/mp4","size":1983468},"aspectRatio":{"width":888,"height":1920}},"record":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreidx3drzczjgeq24lfvbtokl7qokctlag2clq2yx5uyodaoyiloe5i","uri":"at://did:plc:za4pbpzm45dsgw6pcyad6yyy/app.bsky.feed.post/3ld4rptp6v22x"}}},"langs":["en"],"createdAt":"2024-12-14T05:03:04.194Z"}
      """,
      """
      {"text":"","$type":"app.bsky.feed.post","embed":{"$type":"app.bsky.embed.recordWithMedia","media":{"$type":"app.bsky.embed.images","images":[{"alt":"","image":{"$type":"blob","ref":{"$link":"bafkreih77l3xhgf6kj6nfluqux5eq423c2wkk3xqo4cz62xwc3fkyg7rnu"},"mimeType":"image/jpeg","size":255422},"aspectRatio":{"width":1440,"height":1443}}]},"record":{"$type":"app.bsky.embed.record","record":{"cid":"bafyreid4wzky7xogqeuhebb63ez237ktfelkgznfjy67uwi6b3ob2workm","uri":"at://did:plc:5o6k7jvowuyaquloafzn3cfw/app.bsky.feed.post/3ldadyhkmic2s"}}},"langs":["en"],"createdAt":"2024-12-14T05:03:26.689Z"}
      """
    ]

    posts_to_filter
    |> Enum.map(fn post_json_text ->
      post = Jason.decode!(post_json_text)
      {_, filtered?} = VRHose.Ingestor.run_filters(post)
      assert filtered?
    end)
  end
end
