# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arke.Native.DateParser do
  @moduledoc """
  Rust NIFs for ISO8601 parsing and month arithmetic. Binary in, integer
  tuples out (`nil` on failure); the caller rebuilds the structs.

  If the NIF isn't loaded, functions raise `:nif_not_loaded`;
  `Arke.Utils.DatetimeHandler` rescues that and falls back to pure Elixir.
  """
  @version Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :arke,
    crate: "arke_native",
    base_url: "https://github.com/arkemis/arke/releases/download/v#{@version}",
    version: @version,
    targets: ~w(
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
      aarch64-apple-darwin
    ),
    # download the binary instead of building once a release + checksum exist
    force_build: System.get_env("ARKE_FORCE_BUILD_NIF", "true") in ["1", "true"]

  def parse_date(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def parse_time(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def parse_datetime(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def add_months(_y, _m, _d, _months), do: :erlang.nif_error(:nif_not_loaded)
end
