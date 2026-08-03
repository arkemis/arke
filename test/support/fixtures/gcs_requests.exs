# Requests produced by google_api_storage 0.34.0 / google_gax 0.4.1 under
# tesla 1.16.0 — the last version where that stack worked. tesla 1.17+ made
# Compression's :max_body_size mandatory and required binary multipart field
# names, and archived google_gax violates both. These are the requests the
# replacement must reproduce.
#
# Recorded once, not generated on each run. To re-record: set tesla to
# "~> 1.16.0" in mix.exs, restore this recorder, and run it.
%{
  upload_simple: %{
    body: %{
      parts: [
        %{
          body: "{\"name\":\"arke_file/f.png\"}",
          headers: [{"content-type", "application/json"}],
          dispositions: [name: "metadata"]
        },
        %{
          body: "BYTES",
          headers: [{"content-type", "application/octet-stream"}],
          dispositions: [name: "data"]
        }
      ],
      kind: :multipart,
      content_type_params: []
    },
    query: [uploadType: "multipart"],
    url: "https://storage.googleapis.com/upload/storage/v1/b/probe-bucket/o",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :post
  },
  upload_dated_path: %{
    body: %{
      parts: [
        %{
          body: "{\"name\":\"arke_file/2026-08-03 10:11:12.345678Z/my file.png\"}",
          headers: [{"content-type", "application/json"}],
          dispositions: [name: "metadata"]
        },
        %{
          body: "BYTES",
          headers: [{"content-type", "application/octet-stream"}],
          dispositions: [name: "data"]
        }
      ],
      kind: :multipart,
      content_type_params: []
    },
    query: [uploadType: "multipart"],
    url: "https://storage.googleapis.com/upload/storage/v1/b/probe-bucket/o",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :post
  },
  upload_public: %{
    body: %{
      parts: [
        %{
          body: "{\"name\":\"arke_file/f.png\"}",
          headers: [{"content-type", "application/json"}],
          dispositions: [name: "metadata"]
        },
        %{
          body: "BYTES",
          headers: [{"content-type", "application/octet-stream"}],
          dispositions: [name: "data"]
        }
      ],
      kind: :multipart,
      content_type_params: []
    },
    query: [uploadType: "multipart", predefinedAcl: "publicread"],
    url: "https://storage.googleapis.com/upload/storage/v1/b/probe-bucket/o",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :post
  },
  upload_opts_bucket: %{
    body: %{
      parts: [
        %{
          body: "{\"name\":\"arke_file/f.png\"}",
          headers: [{"content-type", "application/json"}],
          dispositions: [name: "metadata"]
        },
        %{
          body: "BYTES",
          headers: [{"content-type", "application/octet-stream"}],
          dispositions: [name: "data"]
        }
      ],
      kind: :multipart,
      content_type_params: []
    },
    query: [uploadType: "multipart"],
    url: "https://storage.googleapis.com/upload/storage/v1/b/opt-bucket/o",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :post
  },
  get_simple: %{
    body: %{body: nil, kind: :raw},
    query: [],
    url: "https://storage.googleapis.com/storage/v1/b/probe-bucket/o/arke_file%2Ff.png",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :get
  },
  get_dated_path: %{
    body: %{body: nil, kind: :raw},
    query: [],
    url: "https://storage.googleapis.com/storage/v1/b/probe-bucket/o/arke_file%2F2026-08-03%2010%3A11%3A12.345678Z%2Fmy%20file.png",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :get
  },
  get_opts_bucket: %{
    body: %{body: nil, kind: :raw},
    query: [],
    url: "https://storage.googleapis.com/storage/v1/b/opt-bucket/o/arke_file%2Ff.png",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :get
  },
  delete_simple: %{
    body: %{body: "", kind: :raw},
    query: [],
    url: "https://storage.googleapis.com/storage/v1/b/probe-bucket/o/arke_file%2Ff.png",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :delete
  },
  delete_dated_path: %{
    body: %{body: "", kind: :raw},
    query: [],
    url: "https://storage.googleapis.com/storage/v1/b/probe-bucket/o/arke_file%2F2026-08-03%2010%3A11%3A12.345678Z%2Fmy%20file.png",
    headers: [
      {"accept-encoding", "gzip, deflate, identity"},
      {"authorization", "Bearer test-token"}
    ],
    method: :delete
  }
}
