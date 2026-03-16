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

defmodule Arke.Core.File do
  @moduledoc """
  Defines a file that can be used to store data
  """

  use Arke.System
  require Logger

  alias Arke.Boundary.ArkeManager

  def file_storage_module(), do: Application.get_env(:arke, :file_storage_module, Arke.Utils.Gcp)

  arke id: :arke_file do
  end

  def before_load(
        %{path: path, content_type: content_type, filename: filename} = _unit,
        :create
      ) do
    {:ok, file_stat} = File.stat(path)
    extension = Path.extname(filename)
    {:ok, binary} = File.read(path)
    path = "arke_file/#{DateTime.to_string(DateTime.utc_now())}"



    unit_data = %{
      binary_data: binary,
      extension: extension,
      size: file_stat.size,
      provider: "gcloud",
      path: path,
      name: filename
    }
    {:ok, unit_data}
  end

  def before_load(opts, _persistence_fn), do: {:ok, opts}

  def on_struct_encode(arke, unit, data, opts) do
    load_files = Keyword.get(opts, :load_files, false)

    with true <- load_files,
      {:ok,signed_url} <- get_url(unit) do
     {:ok, Map.put(data, :signed_url,signed_url )}
    else
      false -> {:ok, data}
      {:error,msg} -> Logger.warning("error while loading the image: #{msg}")
                      {:ok,data}
    end
  end

  def before_create(_, %{data: %{name: name, path: path, binary_data: binary},runtime_data: runtime_data} = unit) do
    is_public_file = is_public?(runtime_data)
    new_unit =  Map.update(unit,:data, unit.data, fn udata -> Map.put(udata,:public,is_public_file) end)
    case file_storage_module().upload_file("#{path}/#{name}", binary,public: is_public_file) do
      {:ok, _object} -> {:ok, new_unit}
      {:error, error} -> {:error, error}
    end
  end


  def before_delete(_, %{data: %{name: name, path: path}} = unit) do
    case file_storage_module().delete_file("#{path}/#{name}") do
      {:ok, _e} -> {:ok, unit}
      {:error, error} -> {:error, error}
    end
  end

  def before_update(_, %{binary_data: binary} = unit) when is_nil(binary), do: {:ok, unit}

  def before_update(_, %{data: %{name: name, path: path, binary_data: binary}} = unit) do
    case file_storage_module().upload_file("#{path}/#{name}", binary) do
      {:ok, _object} -> {:ok, unit}
      {:error, error} -> {:error, error}
    end
  end

  def get_url(%{data: %{public: true}} = unit), do:  file_storage_module().get_public_url(unit)
  def get_url(unit), do: get_signed_url(unit)

  def get_signed_url(%{data: data} = unit) do
    case file_storage_module().get_bucket_file_signed_url("#{data.path}/#{data.name}") do
    {:ok, signed_url} -> {:ok,signed_url}
    {:error,msg} -> {:error,msg}
    end
  end
  defp is_public?(%{link_parameter: %{data: %{public: true}}}), do: true
  defp is_public?(_runtime_data), do: false
end
