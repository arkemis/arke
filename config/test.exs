import Config

config :arke,
  persistence: %{
    arke_postgres: %{
      create: &Arke.Test.Persistence.create/2,
      update: &Arke.Test.Persistence.update/2,
      update_key: &Arke.Test.Persistence.update_key/2,
      delete: &Arke.Test.Persistence.delete/2,
      execute_query: &Arke.Test.Persistence.execute/2,
      get_parameters: &Arke.Test.Persistence.get_parameters/0,
      create_project: &Arke.Test.Persistence.create_project/1,
      delete_project: &Arke.Test.Persistence.delete_project/1
    }
  }
