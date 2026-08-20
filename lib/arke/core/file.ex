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

  alias Arke.Boundary.FileManager
  alias Arke.Hook
  alias Arke.QueryManager
  require Logger

  @refresh_margin 300
  @default_ttl 3600

  def file_storage_module(), do: Application.get_env(:arke, :file_storage_module, Arke.Utils.Gcp)

  arke id: :arke_file do
  end

  before_transaction(:upload, on: :create)
  after_rollback(:remove_uploaded, on: :create)
  before_write(:delete_stored_file, on: :delete)
  after_commit(:evict_cache, on: :delete)

  defp evict_cache(%Hook{unit: %{id: id, metadata: %{project: project}}} = hook) do
    FileManager.remove(id, project)
    {:ok, hook}
  end

  defp remove_uploaded(%Hook{unit: %{data: %{name: name, path: path} = data}} = hook) do
    file_storage_module().delete_file("#{path}/#{name}", bucket: data[:bucket])
    {:ok, hook}
  end

  def before_load(
        %{path: path, content_type: _content_type, filename: filename} = _unit,
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

  def after_struct_encode(_arke, %{metadata: %{project: _project}} = unit, data, opts) do
    load_files = Keyword.get(opts, :load_files, false)

    with true <- load_files,
         {:ok, %{signed_url: signed_url} = _opts} <- get_url(unit) do
      data = Map.put(data, :signed_url, signed_url)
      {:ok, Map.put(data, :signed_url, signed_url)}
    else
      false ->
        {:ok, data}

      {:error, msg} ->
        Logger.warning("error while loading the image: #{inspect(msg)}")
        {:ok, data}
    end
  end

  defp upload(
         %Hook{
           unit:
             %{
               data: %{name: name, path: path, binary_data: binary},
               metadata: %{project: project},
               runtime_data: runtime_data
             } = unit
         } = hook
       ) do
    is_public_file = is_public?(runtime_data)
    bucket = resolve_bucket(runtime_data, project)
    path = "#{project}/#{path}"

    new_unit =
      Map.update(unit, :data, unit.data, fn udata ->
        Map.merge(udata, %{public: is_public_file, bucket: bucket, path: path})
      end)

    case file_storage_module().upload_file("#{path}/#{name}", binary,
           public: is_public_file,
           bucket: bucket
         ) do
      {:ok, _object} -> {:ok, %{hook | unit: new_unit}}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_bucket(%{link_parameter: %{data: %{bucket: bucket}}}, _project)
       when is_binary(bucket),
       do: bucket

  defp resolve_bucket(_runtime_data, project) do
    case QueryManager.get_by(project: :arke_system, arke_id: :arke_project, id: project) do
      %{data: %{bucket: bucket}} when is_binary(bucket) -> bucket
      _ -> nil
    end
  end

  defp delete_stored_file(%Hook{unit: %{data: %{name: name, path: path} = data}} = hook) do
    case file_storage_module().delete_file("#{path}/#{name}", bucket: data[:bucket]) do
      {:ok, _e} -> {:ok, hook}
      {:error, error} -> {:error, error}
    end
  end

  def get_url(unit, opts \\ [])

  def get_url(%{data: %{public: true} = data} = unit, _opts),
    do: file_storage_module().get_public_url(unit, bucket: data[:bucket])

  def get_url(unit, opts), do: get_signed_url(unit, opts)

  def get_signed_url(%{data: data, id: unit_id, metadata: %{project: project}} = unit, opts \\ []) do
    ttl = opts[:expires_in] || Application.get_env(:arke, :signed_url_ttl, @default_ttl)

    with %{signed_url: _signed_url, expiration: expiration} = cached <-
           FileManager.get(unit_id, project),
         true <- serves?(expiration, ttl) do
      {:ok, cached}
    else
      _ ->
        case file_storage_module().get_bucket_file_signed_url(
               "#{data.path}/#{data.name}",
               Keyword.put(opts, :bucket, data[:bucket])
             ) do
          {:ok, result} ->
            FileManager.add(unit, result)
            {:ok, result}

          {:error, msg} ->
            {:error, msg}
        end
    end
  end

  # A url handed out moments before it expires breaks the download mid-flight,
  # and one signed for longer than this caller asked for is a lifetime they
  # never requested, cached from whoever asked for it first. Both re-sign; the
  # margin cannot outgrow the lifetime it trims, or nothing is ever cacheable.
  defp serves?(expiration, ttl) when is_integer(ttl) and ttl > 0 do
    remaining = expiration - System.os_time(:second)
    remaining <= ttl and remaining > ttl - min(@refresh_margin, div(ttl, 2))
  end

  # A ttl the storage module will reject anyway: let it answer, not the cache.
  defp serves?(_expiration, _ttl), do: false

  defp is_public?(%{link_parameter: %{data: %{public: true}}}), do: true
  defp is_public?(_runtime_data), do: false
end
