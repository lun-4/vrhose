#!/usr/bin/env python3
import requests
import time

resp_initial = requests.get("http://localhost:4000/api/v1/hi")
assert resp_initial.status_code == 200
rjson = resp_initial.json()
posts = rjson["batch"]
first = True
while True:
    print("have", len(posts))
    post = posts[-1]
    post_timestamp = int(post["d"]) % 1000
    print("requesting at timestamp", post_timestamp)
    resp_delta = requests.get(f"http://localhost:4000/api/v1/s/{post_timestamp}")
    djson = resp_delta.json()
    delta_posts = djson["batch"]
    if first:
        assert len(delta_posts) <= len(posts)
        first = False
    print("got", len(delta_posts), "delta posts, sleeping...")
    posts = delta_posts
    time.sleep(5)
