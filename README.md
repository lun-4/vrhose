# VRHose

backend for Bluesky Firehose VR, available at https://vrchat.com/home/launch?worldId=wrld_52865286-5286-5286-5286-528652865286

more information here!!! https://bsky.app/profile/natalie.ee/post/3ldcxzpmaxs2e

```
git clone ...
cd vrhose
env MIX_ENV=prod mix deps.get
env MIX_ENV=prod mix zig.get
env MIX_ENV=prod mix compile

# and, for prod
env MIX_ENV=prod mix phx.server
```
