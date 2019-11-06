defmodule Hui.Request do
  @moduledoc """

  Hui.Request module provides underpinning HTTP-based request functions for Solr, including:
  
  - `search/2`, `search/3`
  - `update/2`, `update/3`

  ### Other low-level HTTP client features

  Under the hood, Hui uses `HTTPoison` client to interact with Solr.
  The existing low-level functions of HTTPoison, e.g. `get/1`, `get/3` 
  remain available as part of this module.
  """

  use HTTPoison.Base 
  import Hui.Guards

  @type highlighter_struct :: Hui.H.t | Hui.H1.t | Hui.H2.t | Hui.H3.t
  @type misc_struct :: Hui.S.t | Hui.Sp.t | Hui.M.t
  @type query_struct_list :: list(Hui.Q.t | Hui.D.t | Hui.F.t | highlighter_struct | misc_struct)

  # Use the following equivalent typespecs when checking codes with
  # Dialyzer as the above typespec style doesn'seem to work with the tool.
  #
  #@type highlighter_struct :: %Hui.H{} | %Hui.H1{} | %Hui.H2{} | %Hui.H3{}
  #@type misc_struct :: %Hui.S{} | %Hui.Sp{} | %Hui.M{}
  #@type query_struct_list :: list(%Hui.Q{} | %Hui.D{} | %Hui.F{} | highlighter_struct | misc_struct)

  @type solr_params :: Keyword.t | query_struct_list
  @type solr_url :: atom | Hui.URL.t

  @error_einval %Hui.Error{reason: :einval} # invalid argument exception
  @error_nxdomain %Hui.Error{reason: :nxdomain} # invalid / non existing host or domain

  @doc false
  @spec search(solr_url, boolean, solr_params) :: {:ok, HTTPoison.Response.t} | {:error, Hui.Error.t} | HTTPoison.Response.t
  @deprecated "Please Hui.Query.get/2."
  def search(url, bang \\ false, query)
  def search(%Hui.URL{} = url, bang, query), do: _search(url, bang, query)

  def search(url, true, _query) when is_nil_empty(url), do: raise @error_einval
  def search(url, _bang, _query) when is_nil_empty(url), do: {:error, @error_einval}

  def search(url, bang, query) when is_binary(url), do: _search(%Hui.URL{url: url}, bang, query)
  def search(url, bang, query) when is_atom(url) do
    {status, url_struct} = Hui.URL.configured_url(url)
    case {status, bang} do
      {:ok, _} -> _search(url_struct, bang, query)
      {:error, false} -> {:error, @error_nxdomain}
      {:error, true} -> raise @error_nxdomain
    end
  end
  def search(_,_,_), do: {:error, @error_einval}

  @doc """
  Issues an update request to a specific Solr endpoint, for data uploading and deletion.

  The request sends update data in `Hui.U` struct or binary format to an endpoint
  specified in a `t:Hui.URL.t/0` struct or a URL config key. A content type header is required so that Solr knows the
  incoming data format (JSON, XML etc.) and can process data accordingly.

  ## Example

  ```
    # Specify an endpoint for JSON-formatted update
    headers = [{"Content-type", "application/json"}]
    url = %Hui.URL{url: "http://localhost:8983/solr/collection", handler: "update", headers: headers}
  
    # Solr data / docs - field mapping
    doc1 = %{
      "actor_ss" => ["Ingrid Bergman", "Liv Ullmann", "Lena Nyman", "Halvar Björk"],
      "desc" => "A married daughter who longs for her mother's love is visited by the latter, a successful concert pianist.",
      "directed_by" => ["Ingmar Bergman"],
      "genre" => ["Drama", "Music"],
      "id" => "tt0077711",
      "initial_release_date" => "1978-10-08",
      "name" => "Autumn Sonata"
    }
    doc2 = %{
      "actor_ss" => ["Bibi Andersson", "Liv Ullmann", "Margaretha Krook"],
      "desc" => "A nurse is put in charge of a mute actress and finds that their personas are melding together.",
      "directed_by" => ["Ingmar Bergman"],
      "genre" => ["Drama", "Thriller"],
      "id" => "tt0060827",
      "initial_release_date" => "1967-09-21",
      "name" => "Persona"
    }

    # Hui.U struct command for updating and committing the docs to Solr within 5 seconds
    x = %Hui.U{doc: [doc1, doc2], commitWithin: 5000, overwrite: true}
    {status, resp} = Hui.Request.update(url, x)

    # Delete the docs by IDs, with a URL key from configuration
    {status, resp} = Hui.Request.update(:library_update, %Hui.U{delete_id: ["tt1316540", "tt1650453"]})

    # Commit and optimise index, keep max index segments at 10
    {status, resp} = Hui.Request.update(url, %Hui.U{commit: true, waitSearcher: true, optimize: true, maxSegments: 10})

    # Commit index, expunge deleted docs
    {status, resp} = Hui.Request.update(url, %Hui.U{commit: true, expungeDeletes: true})

    # Direct response or exception in case of failture
    # for implementing bang! style function
    bang = true
    resp = Hui.Request.update(url, bang, json_doc)

    # Binary mode,
    json_binary = # any encoded binary data, e.g. raw JSON from a file
    {status, resp} = Hui.Request.update(url, json_binary)

    # Binary mode, e.g. delete a document via XML binary
    headers = [{"Content-type", "application/xml"}]
    url = %Hui.URL{url: "http://localhost:8983/solr/collection", handler: "update", headers: headers}
    {status, resp} = Hui.Request.update(url, "<delete><id>9780141981727</id></delete>")

  ```

  See [Solr reference](http://lucene.apache.org/solr/guide/uploading-data-with-index-handlers.html)
  for more details on various data commands, types and formats.
  """
  @spec update(solr_url, boolean, binary | Hui.U.t) :: {:ok, HTTPoison.Response.t} | {:error, Hui.Error.t} | HTTPoison.Response.t
  def update(url, bang \\ false, data)
  def update(%Hui.URL{} = url, bang, data) when is_binary(data), do: _update(url, bang, data)
  def update(%Hui.URL{} = url, bang, %Hui.U{} = data), do: _update(url, bang, data |> Hui.U.encode)

  def update(url, true, _data) when is_nil_empty(url), do: raise @error_einval
  def update(url, _bang, _data) when is_nil_empty(url), do: {:error, @error_einval}

  def update(url, bang, %Hui.U{} = data) when is_atom(url), do: update(url, bang, data |> Hui.U.encode)
  def update(url, bang, data) when is_atom(url) and is_binary(data) do
    {status, url_struct} = Hui.URL.configured_url(url)
    case {status, bang} do
      {:ok, _} -> _update(url_struct, bang, data)
      {:error, false} -> {:error, @error_nxdomain}
      {:error, true} -> raise @error_nxdomain
    end
  end
  def update(_,_,_), do: {:error, @error_einval}

  # decode JSON data and return other response formats as
  # raw text
  def process_response_body(""), do: ""
  def process_response_body(body) do
    {status, solr_results} = Poison.decode body
    case status do
      :ok -> solr_results
      :error -> body
    end
  end

  # for keyword lists query 
  defp _search(%Hui.URL{} = url_struct, bang, [head|tail]) when is_tuple(head) do
    url = Hui.URL.to_string(url_struct)
    _search( url <> "?" <> Hui.URL.encode_query([head] ++ tail), url_struct.headers, url_struct.options, bang )
  end

  # for struct-based query 
  defp _search(%Hui.URL{} = url_struct, bang, [head|tail]) when is_map(head) do
    url = Hui.URL.to_string(url_struct)
    _search( url <> "?" <> Enum.map_join([head] ++ tail, "&", &Hui.URL.encode_query/1), url_struct.headers, url_struct.options, bang )
  end
  defp _search(_,true,_), do: raise @error_einval
  defp _search(_,_,_), do: {:error, @error_einval}

  defp _search(url, headers, options, true), do: get!(url, headers, options)
  defp _search(url, headers, options, _bang) do
   {status, resp} = get(url, headers, options)
   case status do
     :ok -> {:ok, resp}
     :error -> {:error, %Hui.Error{reason: resp.reason}}
   end
  end

  defp  _update(%Hui.URL{} = url_struct, true, data), do: Hui.URL.to_string(url_struct) |> post!(data, url_struct.headers, url_struct.options)
  defp  _update(%Hui.URL{} = url_struct, _bang, data) do
    url = Hui.URL.to_string(url_struct)
    {status, resp} = post(url, data, url_struct.headers, url_struct.options)
    case status do
      :ok -> {:ok, resp}
      :error -> {:error, %Hui.Error{reason: resp.reason}}
    end
  end

end