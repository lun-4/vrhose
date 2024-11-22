defmodule VRHose.TimelinerStorage do
  use Zig, otp_app: :vrhose, zig_code_path: "timeliner_storage.zig"
end
