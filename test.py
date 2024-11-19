#!/usr/bin/env python3
import requests

resp_initial = requests.get("http://localhost:4000/api/v1/hi")
assert resp_initial.status_code == 200
rjson = resp_initial.json()
posts = rjson["batch"]
print(len(posts), "posts")
post = posts[-200]
post_timestamp = int(post["d"]) % 1000
print("req post timestamp", post_timestamp)
resp_delta = requests.get(f"http://localhost:4000/api/v1/s/{post_timestamp}")
djson = resp_delta.json()
delta_posts = djson["batch"]
assert len(delta_posts) < len(posts)
print(len(posts), "initial sync posts")
print(len(delta_posts), "delta posts")
