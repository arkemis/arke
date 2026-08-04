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

defmodule Arke.Utils.FileStorage do
  defmacro __using__(_) do
    quote do
      def upload_file(file_name, file_data, opts \\ []), do: {:ok, nil}

      def get_file(file_path, opts \\ []), do: nil

      def get_public_url(unit, opts \\ []), do: {:ok, nil}

      def delete_file(file_path, opts \\ []), do: {:ok, nil}

      def get_bucket_file_signed_url(file_path, opts \\ []), do: {:ok, nil}

      defoverridable upload_file: 3,
                     get_file: 2,
                     get_public_url: 2,
                     delete_file: 2,
                     get_bucket_file_signed_url: 2
    end
  end
end
