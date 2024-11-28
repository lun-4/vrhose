#!/usr/bin/env python3
import os
import requests
import time


def print_rates(rates):
    print("per second:")
    for field in rates:
        data = rates[field]
        print(
            "\t",
            field,
            "\t\t",
            round(data["rate"], 2),
            "\t",
            "(inexact!)" if data["inexact"] else "(ok)",
        )


host = os.environ.get("HOST")
host = host or "http://localhost:4000"

resp_initial = requests.get(f"{host}/api/v1/hi")
assert resp_initial.status_code == 200
rjson = resp_initial.json()
posts = rjson["batch"]
print_rates(rjson["rates"])
first = True
while True:
    print("have", len(posts))
    post = posts[-1]
    post_timestamp = int(post["d"]) % 1000
    print("requesting at timestamp", post_timestamp)
    resp_delta = requests.get(f"{host}/api/v1/s/{post_timestamp}")
    djson = resp_delta.json()
    delta_posts = djson["batch"]
    if first:
        assert len(delta_posts) <= len(posts)
        first = False
    print_rates(djson["rates"])
    print("got", len(delta_posts), "delta posts, sleeping...")
    posts = delta_posts
    time.sleep(2)
