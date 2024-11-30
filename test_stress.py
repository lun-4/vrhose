#!/usr/bin/env python3
import os
import requests
import time
import threading
from concurrent.futures import ThreadPoolExecutor
import queue


def make_request(host):
    try:
        resp_initial = requests.get(f"{host}/api/v1/hi")
        assert resp_initial.status_code == 200
        resp_initial.json()
    except Exception as e:
        print(f"Error in thread: {e}")
        return None


def main():
    host = os.environ.get("HOST")
    host = host or "http://localhost:4000"

    num_threads = 100

    while True:
        with ThreadPoolExecutor(max_workers=num_threads) as executor:
            # Create a list of 10 identical tasks
            futures = [executor.submit(make_request, host) for _ in range(num_threads)]

            # Wait for all requests to complete
            for future in futures:
                future.result()

        # Optional: Add a small delay between batches
        print("tick", time.time())
        time.sleep(0.001)


if __name__ == "__main__":
    main()
